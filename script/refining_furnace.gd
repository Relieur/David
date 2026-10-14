extends Area2D
class_name RefiningFurnace   #精炼炉

const TILE_SIZE := 64

const SMELT_INTERVAL_BASE := 1.5      # 基础烧制耗时（秒）
const SMELT_TIME_PER_LEVEL := 0.25    # 「煅烧速度」每级减少的烧制耗时（秒）
const DOUBLE_SMELT_BASE_CHANCE := 0.15  # 「无中生有」触发双倍产出的基础概率
const CRIT_CHANCE_PER_LEVEL := 0.15     # 「暴击率」每级增加的双倍产出概率
const ORES_PER_INGOT := 1             # 每个原矿产出 1 个铜锭
const ORE_TYPE := "copper"            # 输入：铜原矿
const INGOT_TYPE := "copper_ingot"    # 产出：铜锭

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D

var _smelt_timer: float = 0.0        # 当前铜锭的烧制计时
var _ore_stock: int = 0              # 本炉独立存储的待烧铜矿数量（不与其它炉共享）


func _ready() -> void:
	add_to_group("furnace")
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_align_to_grid()


# 点击精炼炉：若已选中机器人，则手动指挥它前往并卸货到本炉
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("command_return"):
			robot.command_return(self)


# 自动烧制：本炉库存有铜矿时，每「当前烧制耗时」消耗 1 铜矿产出 1 铜锭（铜锭全局共享）
func _process(delta: float) -> void:
	if _ore_stock <= 0:
		if _smelt_timer != 0.0:
			_smelt_timer = 0.0
			queue_redraw()
		return
	var interval := _get_smelt_interval()
	_smelt_timer += delta
	while _smelt_timer >= interval and _ore_stock > 0:
		_smelt_timer -= interval
		_ore_stock -= 1
		# 「无中生有」+「暴击率」：有概率一次烧出两个铜锭
		var gained := ORES_PER_INGOT
		if randf() < _get_double_chance():
			gained = ORES_PER_INGOT * 2
		GameManager.add_item(INGOT_TYPE, gained)
	queue_redraw()


# 当前双倍产出概率：未解锁「无中生有」为 0，否则 15% + 每级「暴击率」+15%
func _get_double_chance() -> float:
	if not GameManager.is_tech_unlocked("double_smelt"):
		return 0.0
	var crit_level := GameManager.get_tech_level("smelt_crit")
	return DOUBLE_SMELT_BASE_CHANCE + CRIT_CHANCE_PER_LEVEL * float(crit_level)


# 当前烧制耗时：基础 1.5 秒，每级「煅烧速度」-0.25 秒
func _get_smelt_interval() -> float:
	var level := GameManager.get_tech_level("smelt_speed")
	return SMELT_INTERVAL_BASE - SMELT_TIME_PER_LEVEL * float(level)


# 投入铜矿：存进本炉独立库存（机器人卸货 / 掉落物飞入）
func deposit_ore(amount: int) -> void:
	_ore_stock += amount
	queue_redraw()


# 本炉当前待烧铜矿数量（供外部查询，如显示/调试）
func get_ore_stock() -> int:
	return _ore_stock


# 烧制进度条（仅在本炉库存有铜矿时显示）
func _draw() -> void:
	if _ore_stock <= 0:
		return
	var ratio := clampf(_smelt_timer / _get_smelt_interval(), 0.0, 1.0)
	var bar_w := 96.0
	var bar_h := 10.0
	var bar_y := -_get_half_height() - 18.0
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.12, 0.12, 0.85))
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), Color(0.95, 0.62, 0.15, 0.95))


# 炉体半高，用于把进度条放在炉子顶部上方
func _get_half_height() -> float:
	if sprite_2d == null or sprite_2d.texture == null:
		return TILE_SIZE
	return sprite_2d.texture.get_size().y * absf(sprite_2d.scale.y) * 0.5


# 对齐：3×3 炉体中心对齐到格子中心，保证正好占据 3×3 格
func _align_to_grid() -> void:
	position.x = floor(position.x / TILE_SIZE) * TILE_SIZE + TILE_SIZE * 0.5
	position.y = floor(position.y / TILE_SIZE) * TILE_SIZE + TILE_SIZE * 0.5
	if collision_shape_2d.shape is RectangleShape2D:
		var rect := collision_shape_2d.shape as RectangleShape2D
		rect.size.x = round(rect.size.x / TILE_SIZE) * TILE_SIZE
		rect.size.y = round(rect.size.y / TILE_SIZE) * TILE_SIZE


func set_center_to(world_pos: Vector2) -> void:
	position = world_pos
	_align_to_grid()


# 判断点是否在炉内
func is_point_inside(world_pos: Vector2) -> bool:
	var local := to_local(world_pos)
	var shape := collision_shape_2d.shape
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var half: Vector2 = rect.size * 0.5
		return abs(local.x) <= half.x and abs(local.y) <= half.y
	elif shape is CircleShape2D:
		var circle := shape as CircleShape2D
		return local.length() <= circle.radius
	return false
