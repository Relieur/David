extends Node2D

@onready var tilemap = $TileMapLayer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
@onready var ware_house: WareHouse = $WareHouse
@onready var robot_container: Node2D = $RobotContainer
@onready var decoration_container: Node2D = $DecorationContainer

# ==================== 预加载 ====================
const DROPPED_ITEM_SCENE: PackedScene = preload("res://scene/dropped_item.tscn")
const ROBOT_SCENE: PackedScene = preload("res://scene/robot.tscn")
const DECORATION_SCENE: PackedScene = preload("res://scene/decoration.tscn")

# ==================== 尺寸 ====================
const TILE_SIZE := 64
const MAP_SIZE := Vector2i(128, 128)

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
const REPRODUCE_MAX := 80             # 繁殖能力：机器人数量上限

# 玩家在场景里手动放置的矿点（按场景树顺序排列，开局全部隐藏）
var _placed_patches: Array = []
var _reveal_index: int = 0
var _reproduce_timer: float = 0.0      # 繁殖计时


func _ready() -> void:
	generate_world()
	_scatter_decorations()
	_place_warehouse()
	_setup_camera()
	_spawn_robots()
	_collect_placed_patches()
	_reveal_next_patch()
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	# [测试] 开局赠送 100 铜矿，方便测试科技树，后期删除
	GameManager.add_item("copper", 100)


# ==================== 仓库居中 ====================
func _place_warehouse() -> void:
	var center_cell := MAP_SIZE / 2
	var pos := _cell_to_world(center_cell)
	ware_house.set_center_to(pos)


# ==================== 生成机器人 ====================
func _spawn_robots() -> void:
	for i in INITIAL_ROBOT_COUNT:
		_spawn_robot()


# 生成一个机器人，随机放在仓库周围
func _spawn_robot() -> void:
	var robot := ROBOT_SCENE.instantiate()
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * TILE_SIZE * 1.5
	robot.global_position = ware_house.global_position + offset
	robot_container.add_child(robot)


# 每帧驱动繁殖计时
func _process(delta: float) -> void:
	_tick_reproduce(delta)


# 繁殖能力：解锁后每隔 REPRODUCE_INTERVAL 秒在仓库周围生成一个新机器人，直到上限
func _tick_reproduce(delta: float) -> void:
	if not GameManager.is_tech_unlocked("reproduce"):
		return
	if robot_container.get_child_count() >= REPRODUCE_MAX:
		return
	_reproduce_timer += delta
	if _reproduce_timer >= REPRODUCE_INTERVAL:
		_reproduce_timer = 0.0
		_spawn_robot()
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
	camera_2d.set_target(ware_house.global_position)
	camera_2d.zoom = Vector2(2.0, 2.0)
	camera_2d.map_size_px = Vector2(MAP_SIZE) * TILE_SIZE
	camera_2d.viewport_size = get_viewport_rect().size
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


# 依次显示下一个预放置的矿点
func _reveal_next_patch() -> void:
	if _reveal_index >= _placed_patches.size():
		print("没有更多矿点了")
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
