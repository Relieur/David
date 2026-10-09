extends Node2D

@onready var tilemap = $TileMapLayer
@onready var ore_container: Node2D = $OreContainer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
@onready var ware_house: WareHouse = $WareHouse
@onready var robot_container: Node2D = $RobotContainer

# ==================== 地图种子 ====================
@export var map_seed: int = 0

# ==================== 预加载 ====================
const ORE_SCENE: PackedScene = preload("res://scene/ore.tscn")
const DROPPED_ITEM_SCENE: PackedScene = preload("res://scene/dropped_item.tscn")
const ROBOT_SCENE: PackedScene = preload("res://scene/robot.tscn")

# ==================== 尺寸 ====================
const TILE_SIZE := 64
const MAP_SIZE := Vector2i(128, 128)

# ==================== 矿区生成 ====================
const ORE_PATCH_MIN := 1
const ORE_PATCH_MAX := 6
const NO_ORE_RADIUS := 10.0
const TARGET_PATCH_COUNT := 40
const MAX_ORE_ATTEMPTS := 3000

# ==================== 机器人 ====================
const INITIAL_ROBOT_COUNT := 3

# ==================== 运行时数据 ====================
# 所有矿区（每个元素是格子数组），按离仓库由近到远排序
var _ore_patches: Array = []
# 当前解锁到第几块矿区
var _current_patch_index: int = -1


func _ready() -> void:
	generate_world()
	_place_warehouse()
	_setup_camera()
	_spawn_robots()
	GameManager.tech_unlocked.connect(_on_tech_unlocked)


# ==================== 仓库居中 ====================
func _place_warehouse() -> void:
	var center_cell := MAP_SIZE / 2
	var pos := Vector2(center_cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	ware_house.set_center_to(pos)


# ==================== 生成机器人 ====================
func _spawn_robots() -> void:
	for i in INITIAL_ROBOT_COUNT:
		var robot := ROBOT_SCENE.instantiate()
		var angle := float(i) / float(INITIAL_ROBOT_COUNT) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * TILE_SIZE * 1.5
		robot.global_position = ware_house.global_position + offset
		robot_container.add_child(robot)

#取消选择机器人
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_RIGHT:
		GameManager.deselect_robot()
		get_viewport().set_input_as_handled()


# ==================== 生成世界 ====================
func generate_world() -> void:
	if map_seed == 0:
		map_seed = randi()
	print("种子：", map_seed)

	# 铺满地面
	var ground_cells: Array[Vector2i] = []
	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			ground_cells.append(Vector2i(x, y))
	tilemap.set_cells_terrain_connect(ground_cells, 0, 1)

	# 生成矿区列表
	var center_cell := MAP_SIZE / 2
	_generate_ore_patches(center_cell)

	# 开局只显示第 0 块矿区
	if _ore_patches.size() > 0:
		_spawn_patch(0)
		_current_patch_index = 0

	print("矿区总数%d" % _ore_patches.size())


# ==================== 摄像机 ====================
func _setup_camera() -> void:
	camera_2d.set_target(ware_house.global_position)
	camera_2d.zoom = Vector2(2.0, 2.0)
	camera_2d.map_size_px = Vector2(MAP_SIZE) * TILE_SIZE
	camera_2d.viewport_size = get_viewport_rect().size
	camera_2d.make_current()


# ==================== 生成矿区列表 ====================
func _generate_ore_patches(center_cell: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	var occupied := {}
	var patches: Array = []
	var attempts := 0

	while patches.size() < TARGET_PATCH_COUNT and attempts < MAX_ORE_ATTEMPTS:
		attempts += 1

		var cx := rng.randi_range(0, MAP_SIZE.x - 1)
		var cy := rng.randi_range(0, MAP_SIZE.y - 1)

		if Vector2(cx, cy).distance_to(Vector2(center_cell)) < NO_ORE_RADIUS:
			continue

		var w := rng.randi_range(ORE_PATCH_MIN, ORE_PATCH_MAX)
		var h := rng.randi_range(ORE_PATCH_MIN, ORE_PATCH_MAX)

		if cx + w > MAP_SIZE.x or cy + h > MAP_SIZE.y:
			continue

		var ok := true
		for dx in w:
			for dy in h:
				if occupied.has(Vector2i(cx + dx, cy + dy)):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue

		var patch: Array[Vector2i] = []
		for dx in w:
			for dy in h:
				var c := Vector2i(cx + dx, cy + dy)
				occupied[c] = true
				patch.append(c)
		patches.append(patch)

	patches.sort_custom(func(a, b):
		return _patch_dist(a, center_cell) < _patch_dist(b, center_cell)
	)
	_ore_patches = patches


# 矿区中心到目标格子的距离平方
func _patch_dist(patch: Array, center: Vector2i) -> float:
	var mid := _patch_center(patch)
	return Vector2(mid).distance_squared_to(Vector2(center))


# 求矿区中心
func _patch_center(patch: Array) -> Vector2i:
	var sum := Vector2i.ZERO
	for c in patch:
		sum += c
	return sum / patch.size()


# ==================== 实例化一块矿区 ====================
func _spawn_patch(index: int) -> void:
	if index < 0 or index >= _ore_patches.size():
		return
	var patch: Array = _ore_patches[index]
	for cell in patch:
		_spawn_ore(cell)
	print("显示第%d块矿区，共%d个格子" % [index, patch.size()])


# ==================== 实例化一个矿石 ====================
func _spawn_ore(cell: Vector2i) -> void:
	var copper := ORE_SCENE.instantiate()
	copper.global_position = Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	copper.ore_type = "copper"
	copper.amount = 1
	ore_container.add_child(copper)
	#copper.mined.connect(_on_copper_mined.bind(copper))


# ==================== 科技解锁回调 ====================
func _on_tech_unlocked(tech_id: String) -> void:
	if tech_id == "unlock_more_ores":
		await  get_tree().create_timer(0.3).timeout
		var next_index := _current_patch_index + 1
		if next_index < _ore_patches.size():
			_spawn_patch(next_index)
			_current_patch_index = next_index

			var patch_center := _patch_center(_ore_patches[next_index])
			var target_pos := Vector2(patch_center) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
			camera_2d.fly_to(target_pos)
		else:
			print("已经没有更多矿区了")


# ==================== 采集回调 ====================
func _on_copper_mined(ore_type: String, amount: int, ore: Node2D) -> void:
	var drop := DROPPED_ITEM_SCENE.instantiate()

	var angle := randf() * TAU
	var radius := randf_range(20.0, 40.0)
	var offset := Vector2(cos(angle), sin(angle)) * radius

	drop.global_position = ore.global_position + offset
	drop.item_type = ore_type
	drop.amount = amount
	drop_container.add_child(drop)

	print("获得%s x %d" % [ore_type, amount])
