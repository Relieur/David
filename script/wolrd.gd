extends Node2D

@onready var tilemap = $TileMapLayer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
var furnace: RefiningFurnace                # 主炉引用，由 _collect_placed_furnaces() 赋值（炉子挂在 RobotContainer 下参与 y-sort）
@onready var robot_container: Node2D = $RobotContainer
@onready var decoration_container: Node2D = $DecorationContainer

# ==================== 预加载 ====================
const DROPPED_ITEM_SCENE: PackedScene = preload("res://scene/dropped_item.tscn")
const ROBOT_SCENE: PackedScene = preload("res://scene/robot.tscn")
const DECORATION_SCENE: PackedScene = preload("res://scene/decoration.tscn")

# ==================== 尺寸 ====================
const TILE_SIZE := 64
const MAP_SIZE := Vector2i(128, 72)  # 16:9 比例（8192×4608），裁剪后缩到最小时铺满视口无留白

# ==================== 装饰散布 ====================
const DECORATION_TEXTURES: Array[Texture2D] = [
	preload("res://art/decoration/deco_1x1.png"),
	preload("res://art/decoration/deco_2x2.png"),
	preload("res://art/decoration/deco_2x3.png"),
	preload("res://art/decoration/deco_4x4.png"),
	preload("res://art/decoration/deco_4x6.png"),
]

@export var decoration_spacing := 15    # 装饰网格间距（单位：格），值越小越密
@export var decoration_seed := 20261011  # 随机种子，调整可重排装饰布局

# ==================== 机器人 ====================
const INITIAL_ROBOT_COUNT := 0
const REPRODUCE_INTERVAL := 15.0      # 繁殖能力：每隔多少秒自动生成一个机器人

# 玩家在场景里手动放置的矿点（按场景树顺序排列，开局全部隐藏）
var _placed_patches: Array = []
var _reveal_index: int = 0
var _reproduce_timer: float = 0.0      # 繁殖计时


func _ready() -> void:
	generate_world()
	_scatter_decorations()
	# 精炼炉：位置完全按场景里手动摆放的位置来（不再自动居中 / 自动散布），
	# 开局只启用名字顺序里的第一个，其余靠「扩建精炼炉」科技逐级出现
	_collect_placed_furnaces()
	_setup_camera()
	# 机器人按 y 坐标自动排序（下方遮盖上方），替代手动每帧改 z_index，减少重排开销
	robot_container.y_sort_enabled = true
	_spawn_robots()
	_collect_placed_patches()
	# 初始只显示 1 个矿点，其余通过 unlock_more_ores 科技升级解锁（每次升级 reveal 3 个）
	if _placed_patches.size() > 0:
		_set_patch_active(_placed_patches[0], true)
		_reveal_index = 1
	# 继续游戏：按存档恢复矿点显示数量 / 炉子启用数量 / 机器人数量
	if GameManager.restore_mode:
		_apply_restore()
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	# [测试] 开局赠送 100000 铜锭，方便测试科技树，后期删除
	# GameManager.add_item("copper_ingot", 100000)


# ==================== 存档恢复 / 自动保存 ====================
const AUTOSAVE_INTERVAL := 60.0       # 每 60 秒自动保存一次
var _autosave_timer: float = 0.0


# 继续游戏：把存档里的进度还原到场景（科技等级 / 库存 / 研究所阶段已在 load_game 还原到 GameManager）
func _apply_restore() -> void:
	# 矿点：开局显示 1 个 + 每级「新的资源点」reveal 3 个
	var ore_lv := GameManager.get_tech_level("unlock_more_ores")
	var target_patches := mini(1 + ore_lv * 3, _placed_patches.size())
	while _reveal_index < target_patches:
		_set_patch_active(_placed_patches[_reveal_index], true)
		_reveal_index += 1
	# 炉子：开局启用 1 个 + 每级「扩建精炼炉」启用下一个
	var furnace_target := mini(1 + GameManager.get_tech_level("add_furnace"), _placed_furnaces.size())
	while _reveal_furnace_index < furnace_target:
		if is_instance_valid(_placed_furnaces[_reveal_furnace_index]):
			_placed_furnaces[_reveal_furnace_index].set_active(true)
		_reveal_furnace_index += 1
	# 机器人：恢复存档时的数量（繁殖产生的也计入），不超过当前上限
	var robots_target := mini(GameManager.get_restore_robot_count(), _get_robot_max())
	while _count_robots() < robots_target:
		if not _spawn_robot():
			break
	# 机器人记忆的矿区：按生成顺序逐个还原
	_restore_robot_memory()
	GameManager.clear_restore_mode()
	print("已从存档恢复：机器人 %d / 矿点 %d / 炉子 %d" % [_count_robots(), _reveal_index, _reveal_furnace_index])


# 按存档顺序给机器人还原已记忆的矿区（存档存的是节点名，这里按名字找回 OrePatch）
func _restore_robot_memory() -> void:
	var memories: Array = GameManager.get_restore_robot_memory()
	if memories.is_empty():
		return
	var idx := 0
	for child in robot_container.get_children():
		if not child is Robot:
			continue
		if idx >= memories.size():
			break
		var patches: Array = []
		for patch_name in memories[idx]:
			var node := get_node_or_null(NodePath(String(patch_name)))
			if node != null and node is OrePatch:
				patches.append(node)
		(child as Robot).inherit_patches(patches)
		idx += 1


# 每 60 秒自动保存；窗口关闭（退出游戏）时也保存一次
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameManager.save_game()


# ==================== 精炼炉（沿用场景里摆放的位置） ====================
# 「扩建精炼炉」的升级次数（固定 5 次）
const FURNACE_UPGRADE_MAX := 5

# 玩家在场景里手动摆放的炉子；开局只启用名字顺序里的第一个，
# 之后每升一级「扩建精炼炉」就按名字顺序启用下一个。
var _placed_furnaces: Array[RefiningFurnace] = []
var _reveal_furnace_index: int = 0


func _collect_placed_furnaces() -> void:
	_placed_furnaces.clear()
	_reveal_furnace_index = 0
	for node in get_tree().get_nodes_in_group("furnace"):
		if node is RefiningFurnace:
			_placed_furnaces.append(node)
	# 出现顺序 = 名字顺序：Furnace → Furnace2 → Furnace3 → …
	_placed_furnaces.sort_custom(_furnace_order_cmp)
	for f in _placed_furnaces:
		f.set_active(false)
	if _placed_furnaces.is_empty():
		push_warning("场景里没有预放置任何精炼炉")
		return
	furnace = _placed_furnaces[0]
	furnace.set_active(true)
	_reveal_furnace_index = 1
	# 「扩建精炼炉」升级次数固定 5 次：开局 1 个炉子 + 升级 5 次 = 最多 6 个炉子。
	# 场景里摆的炉子更多时按炉子数量自动提升，避免多出来的炉子永远出不来。
	GameManager.set_tech_max_level("add_furnace", maxi(FURNACE_UPGRADE_MAX, _placed_furnaces.size() - 1))


# 排序比较：取名字结尾的数字作为序号（无数字视作 0），序号相同再按名字比
func _furnace_order_cmp(a: RefiningFurnace, b: RefiningFurnace) -> bool:
	var na := _name_tail_number(a.name)
	var nb := _name_tail_number(b.name)
	if na != nb:
		return na < nb
	return String(a.name) < String(b.name)


func _name_tail_number(node_name: StringName) -> int:
	var s := String(node_name)
	var digits := ""
	for i in range(s.length() - 1, -1, -1):
		var code := s.unicode_at(i)
		if code < 48 or code > 57:
			break
		digits = s[i] + digits
	return int(digits) if digits != "" else 0


# 生成机器人
func _get_robot_max() -> int:
	return GameManager.get_robot_max()


func _spawn_robots() -> void:
	for i in INITIAL_ROBOT_COUNT:
		_spawn_robot()


# 统计场上真实的机器人数量。
# 注意：RobotContainer 下还挂着精炼炉（参与 y-sort），
# 不能直接用 get_child_count()，否则会把炉子算成机器人。
func _count_robots() -> int:
	var n := 0
	for child in robot_container.get_children():
		if child is Robot:
			n += 1
	return n


# 生成一个机器人，随机放在仓库周围；达到数量上限时返回 false
func _spawn_robot() -> bool:
	if _count_robots() >= _get_robot_max():
		return false
	var robot := ROBOT_SCENE.instantiate() as Robot
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * TILE_SIZE * 1.5
	robot.global_position = furnace.global_position + offset
	robot_container.add_child(robot)
	_inherit_patches(robot)
	# 第一个机器人出现时，在上方提示框提示如何指挥机器人挖矿
	if _count_robots() == 1:
		_show_first_robot_hint()
	return true


# 上方提示框是队列播放，不会与其它提示互相抵消
func _show_first_robot_hint() -> void:
	var hud := get_node_or_null("UILayer/HudUI")
	if hud != null and hud.has_method("show_hint"):
		hud.show_hint("选中机器人再点击矿可以让机器人自动挖矿，右键取消选中")


# 汇总场上所有机器人已记忆的矿区（去重、过滤失效节点）
func _collect_all_patches() -> Array:
	var patches: Array = []
	for child in robot_container.get_children():
		if not child is Robot:
			continue
		for patch in (child as Robot).known_patches:
			if is_instance_valid(patch) and not patches.has(patch):
				patches.append(patch)
	return patches


# 新机器人继承已有机器人的矿区记忆（需解锁「信息交流能力」）
func _inherit_patches(new_robot: Robot) -> void:
	if not GameManager.is_tech_unlocked("info_share"):
		return
	new_robot.inherit_patches(_collect_all_patches())


# 解锁「信息交流能力」时：把全体机器人已有的矿区记忆汇总后分发给所有人，
# 使解锁前生成的机器人也一并获得共享（含它们在解锁前记住的矿区）
func _sync_all_patches() -> void:
	var all_patches := _collect_all_patches()
	for child in robot_container.get_children():
		if child is Robot:
			(child as Robot).inherit_patches(all_patches)


# 每帧驱动繁殖计时
func _process(delta: float) -> void:
	_tick_reproduce(delta)
	# 自动保存计时
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		GameManager.save_game()


# 繁殖能力：解锁后每隔 REPRODUCE_INTERVAL 秒在仓库周围生成一个新机器人，直到上限
func _tick_reproduce(delta: float) -> void:
	if not GameManager.is_tech_unlocked("reproduce"):
		return
	if _count_robots() >= _get_robot_max():
		return
	_reproduce_timer += delta
	if _reproduce_timer >= REPRODUCE_INTERVAL:
		_reproduce_timer = 0.0
		if _spawn_robot():
			print("机器人繁殖，当前数量 %d" % _count_robots())


# 取消选择机器人
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_RIGHT:
		GameManager.deselect_robot()
		get_viewport().set_input_as_handled()


# ==================== 生成世界 ====================
func generate_world() -> void:
	# 铺满地面
	var ground_cells: Array[Vector2i] = []
	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			ground_cells.append(Vector2i(x, y))
	tilemap.set_cells_terrain_connect(ground_cells, 0, 1)


# ==================== 随机均匀散布装饰 ====================
func _scatter_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = decoration_seed
	var map_px := Vector2(MAP_SIZE) * TILE_SIZE
	var spacing_px := float(decoration_spacing) * TILE_SIZE
	var cols := int(map_px.x / spacing_px)
	var rows := int(map_px.y / spacing_px)
	for gx in cols:
		for gy in rows:
			var tex := DECORATION_TEXTURES[rng.randi_range(0, DECORATION_TEXTURES.size() - 1)]
			var deco := DECORATION_SCENE.instantiate() as Sprite2D
			deco.texture = tex
			# 每个网格单元内随机取一点，做到“随机但均匀”
			var jitter := Vector2(rng.randf() * spacing_px, rng.randf() * spacing_px)
			var half := tex.get_size() * 0.5
			var pos := Vector2(gx * spacing_px, gy * spacing_px) + jitter
			pos.x = clampf(pos.x, half.x, map_px.x - half.x)
			pos.y = clampf(pos.y, half.y, map_px.y - half.y)
			deco.position = pos
			decoration_container.add_child(deco)


# ==================== 摄像机 ====================
func _setup_camera() -> void:
	camera_2d.set_target(furnace.global_position)
	camera_2d.zoom = Vector2(2.0, 2.0)
	camera_2d.map_size_px = Vector2(MAP_SIZE) * TILE_SIZE
	camera_2d.viewport_size = get_viewport_rect().size
	camera_2d.recompute_zoom_min()
	camera_2d.make_current()


# ==================== 收集并隐藏场景里预放置的矿点 ====================
func _collect_placed_patches() -> void:
	_placed_patches.clear()
	_reveal_index = 0
	for child in get_children():
		if child is Ore or child is OrePatch:
			_placed_patches.append(child)
			_set_patch_active(child, false)
			if child is OrePatch and not child.mineral_dropped.is_connected(_on_mineral_dropped):
				child.mineral_dropped.connect(_on_mineral_dropped)


# ==================== 科技解锁回调 ====================
func _on_tech_unlocked(tech_id: String) -> void:
	if tech_id == "unlock_more_ores":
		await get_tree().create_timer(0.3).timeout
		_reveal_next_patch()
	elif tech_id == "ore_durability":
		for child in get_children():
			if child is OrePatch:
				child.refill_to_max()
	elif tech_id == "add_robot":
		if not _spawn_robot():
			# 正常情况下不会发生（购买前 can_unlock_tech 已判定过上限）。
			# 真到了这里说明两处计数口径又不一致了，铜锭已被扣掉，必须报警排查。
			push_warning("添加机器人失败：已扣除铜锭但未生成机器人（机器人 %d / 上限 %d）"
				% [_count_robots(), _get_robot_max()])
	elif tech_id == "add_furnace":
		_reveal_next_furnace()
	elif tech_id == "info_share":
		_sync_all_patches()


# 「扩建精炼炉」：按名字顺序启用下一个预放置的炉子（位置就是场景里摆放的位置）
func _reveal_next_furnace() -> void:
	if _reveal_furnace_index >= _placed_furnaces.size():
		print("没有更多预放置的精炼炉了（已启用 %d/%d）" % [_reveal_furnace_index, _placed_furnaces.size()])
		return
	var next_furnace: RefiningFurnace = _placed_furnaces[_reveal_furnace_index]
	_reveal_furnace_index += 1
	if not is_instance_valid(next_furnace):
		return
	next_furnace.set_active(true)
	print("扩建精炼炉：启用 %s，已启用 %d/%d" % [next_furnace.name, _reveal_furnace_index, _placed_furnaces.size()])


# 依次显示下一个预放置的矿点
func _reveal_next_patch() -> void:
	for i in range(3):
		if _reveal_index >= _placed_patches.size():
			print("没有更多矿点了（已显示 %d/%d）" % [_reveal_index, _placed_patches.size()])
			return
		_set_patch_active(_placed_patches[_reveal_index], true)
		_reveal_index += 1
	print("显示矿点 %d/%d" % [_reveal_index, _placed_patches.size()])


# 切换矿点的显示与可交互（OrePatch 需递归处理其子 Ore）
func _set_patch_active(node: Node, active: bool) -> void:
	node.visible = active
	if node is Ore:
		node.input_pickable = active
	if active and node is OrePatch and node.has_method("refresh_visual"):
		# 刚 reveal：强制刷新一次外观（隐藏期间跳过了视觉更新）
		node.refresh_visual()
	for child in node.get_children():
		if child is Ore:
			child.visible = active
			child.input_pickable = active


# ==================== 矿物掉落回调 ====================
func _on_mineral_dropped(world_pos: Vector2) -> void:
	var drop := DROPPED_ITEM_SCENE.instantiate()
	var angle := randf() * TAU
	var radius := randf_range(10.0, 30.0)
	var offset := Vector2(cos(angle), sin(angle)) * radius
	drop.global_position = world_pos + offset
	drop.item_type = "copper"
	drop.amount = 1
	drop_container.add_child(drop)
	print("掉落矿物 x1")
