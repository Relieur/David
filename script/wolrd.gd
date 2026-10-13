extends Node2D

@onready var tilemap = $TileMapLayer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
@onready var furnace: RefiningFurnace = $Furnace
@onready var robot_container: Node2D = $RobotContainer
@onready var decoration_container: Node2D = $DecorationContainer

# ==================== 预加载 ====================
const DROPPED_ITEM_SCENE: PackedScene = preload("res://scene/dropped_item.tscn")
const ROBOT_SCENE: PackedScene = preload("res://scene/robot.tscn")
const DECORATION_SCENE: PackedScene = preload("res://scene/decoration.tscn")
const FURNACE_SCENE: PackedScene = preload("res://scene/refining_furnace.tscn")

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
const ROBOT_MAX_BASE := 20            # 机器人数量上限：基础值
const ROBOT_MAX_PER_LEVEL := 20       # 「机器人数量上限」科技每级增加的数量

# 玩家在场景里手动放置的矿点（按场景树顺序排列，开局全部隐藏）
var _placed_patches: Array = []
var _reveal_index: int = 0
var _reproduce_timer: float = 0.0      # 繁殖计时


func _ready() -> void:
	generate_world()
	_scatter_decorations()
	_place_furnace()
	_setup_camera()
	# 机器人按 y 坐标自动排序（下方遮盖上方），替代手动每帧改 z_index，减少重排开销
	robot_container.y_sort_enabled = true
	_spawn_robots()
	_collect_placed_patches()
	# 初始只显示 1 个矿点，其余通过 unlock_more_ores 科技升级解锁（每次升级 reveal 3 个）
	if _placed_patches.size() > 0:
		_set_patch_active(_placed_patches[0], true)
		_reveal_index = 1
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	# [测试] 开局赠送 100000 铜锭，方便测试科技树，后期删除
	GameManager.add_item("copper_ingot", 100000)


# ==================== 精炼炉居中 ====================
func _place_furnace() -> void:
	var center_cell := MAP_SIZE / 2
	var pos := _cell_to_world(center_cell)
	furnace.set_center_to(pos)


# ==================== 生成机器人 ====================
# 机器人数量上限：基础 20 + 「机器人数量上限」科技每级 +20
func _get_robot_max() -> int:
	return ROBOT_MAX_BASE + ROBOT_MAX_PER_LEVEL * GameManager.get_tech_level("robot_count")


func _spawn_robots() -> void:
	for i in INITIAL_ROBOT_COUNT:
		_spawn_robot()


# 生成一个机器人，随机放在仓库周围；达到数量上限时返回 false
func _spawn_robot() -> bool:
	if robot_container.get_child_count() >= _get_robot_max():
		return false
	var robot := ROBOT_SCENE.instantiate() as Robot
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * TILE_SIZE * 1.5
	robot.global_position = furnace.global_position + offset
	robot_container.add_child(robot)
	_inherit_patches(robot)
	return true


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


# 繁殖能力：解锁后每隔 REPRODUCE_INTERVAL 秒在仓库周围生成一个新机器人，直到上限
func _tick_reproduce(delta: float) -> void:
	if not GameManager.is_tech_unlocked("reproduce"):
		return
	if robot_container.get_child_count() >= _get_robot_max():
		return
	_reproduce_timer += delta
	if _reproduce_timer >= REPRODUCE_INTERVAL:
		_reproduce_timer = 0.0
		if _spawn_robot():
			print("机器人繁殖，当前数量 %d" % robot_container.get_child_count())


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


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5


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
		_spawn_robot()
	elif tech_id == "add_furnace":
		_spawn_furnace()
	elif tech_id == "info_share":
		_sync_all_patches()


# 「扩建精炼炉」：在整张地图上均匀散布一个新炉子，与现有炉子并行烧制
const FURNACE_EDGE_MARGIN := 6   # 炉子距地图边缘的最小格数
func _spawn_furnace() -> void:
	var existing: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("furnace"):
		if node is Node2D:
			existing.append(node)
	# 在可用格子里挑选离所有已有炉子最远的一格，实现“均匀散布”
	var best_cell := Vector2i.ZERO
	var best_dist := -1.0
	for x in range(FURNACE_EDGE_MARGIN, MAP_SIZE.x - FURNACE_EDGE_MARGIN):
		for y in range(FURNACE_EDGE_MARGIN, MAP_SIZE.y - FURNACE_EDGE_MARGIN):
			var pos := _cell_to_world(Vector2i(x, y))
			var min_dist := INF
			for f in existing:
				min_dist = minf(min_dist, pos.distance_squared_to(f.global_position))
			if min_dist > best_dist:
				best_dist = min_dist
				best_cell = Vector2i(x, y)
	var new_furnace := FURNACE_SCENE.instantiate() as RefiningFurnace
	add_child(new_furnace)
	new_furnace.set_center_to(_cell_to_world(best_cell))
	print("扩建精炼炉，当前炉子数量 %d" % get_tree().get_nodes_in_group("furnace").size())


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
