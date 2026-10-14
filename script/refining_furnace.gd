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

const FLOATER_DURATION := 0.9         # 「+N」浮动文字的存在时长（秒）
const FLOATER_RISE := 42.0            # 「+N」浮动文字的上升距离（像素）

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D

var _smelt_timer: float = 0.0        # 当前铜锭的烧制计时
var _ore_stock: int = 0              # 本炉独立存储的待烧铜矿数量（不与其它炉共享）
var _is_active: bool = true          # 是否已启用（预放置的炉子开局只有名字最小的那个启用）
var _floaters: Array = []            # 烧制完成时「+N」浮动效果列表
var _stock_label: Label = null       # 炉内矿量显示（UI）
var _label_stock: int = -1           # 上次刷新标签时的矿量（用于避免重复刷新）


func _ready() -> void:
	add_to_group("furnace")
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_align_to_grid()
	_create_stock_label()


# 创建「炉内矿量」显示标签（放在炉体下方）
func _create_stock_label() -> void:
	_stock_label = Label.new()
	_stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stock_label.add_theme_font_size_override("font_size", 32)
	_stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stock_label.z_index = 1
	const LABEL_W := 160.0
	const LABEL_H := 48.0
	_stock_label.size = Vector2(LABEL_W, LABEL_H)
	_stock_label.position = Vector2(-LABEL_W * 0.5, _get_half_height() + 2.0)
	add_child(_stock_label)
	_update_stock_label()


# 刷新矿量文字：有矿时高亮，空炉时灰显（矿量未变时直接跳过）
func _update_stock_label() -> void:
	if _stock_label == null or _label_stock == _ore_stock:
		return
	_label_stock = _ore_stock
	_stock_label.text = "矿 %d" % _ore_stock
	_stock_label.add_theme_color_override(
		"font_color",
		Color(0.95, 0.25, 0.25, 1.0) if _ore_stock > 0 else Color(0.68, 0.30, 0.30, 0.9)
	)


func is_active() -> bool:
	return _is_active


# 启用 / 停用：停用的炉子隐藏、停止烧制、并退出 "furnace" 分组，
# 这样机器人寻路和掉落物「找最近的炉子」都不会选中它
func set_active(active: bool) -> void:
	_is_active = active
	visible = active
	input_pickable = active
	set_process(active)
	if active:
		if not is_in_group("furnace"):
			add_to_group("furnace")
	else:
		if is_in_group("furnace"):
			remove_from_group("furnace")
		_smelt_timer = 0.0


# 点击精炼炉：若已选中机器人，则手动指挥它前往并卸货到本炉
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("command_return"):
			robot.command_return(self)


# 自动烧制：本炉库存有铜矿时，每「当前烧制耗时」消耗 1 铜矿产出 1 铜锭（铜锭全局共享）
func _process(delta: float) -> void:
	var dirty := _update_floaters(delta)
	if not _is_active:
		if dirty:
			queue_redraw()
		return
	if _ore_stock > 0:
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
			# 每烧制完成一次，在炉子上方弹出一个「+N」
			_spawn_floater("+%d" % gained)
		_update_stock_label()
		dirty = true
	elif _smelt_timer != 0.0:
		_smelt_timer = 0.0
		dirty = true
	if dirty:
		queue_redraw()


# ==================== 「+N」浮动效果 ====================
func _spawn_floater(text: String) -> void:
	_floaters.append({
		"text": text,
		"elapsed": 0.0,
		"offset_x": randf_range(-14.0, 14.0),
		"offset_y": randf_range(-4.0, 4.0),
	})


# 推进浮动效果计时，返回是否需要重绘
func _update_floaters(delta: float) -> bool:
	if _floaters.is_empty():
		return false
	var alive: Array = []
	for f in _floaters:
		f["elapsed"] = float(f["elapsed"]) + delta
		if float(f["elapsed"]) < FLOATER_DURATION:
			alive.append(f)
	_floaters = alive
	return true


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
	_update_stock_label()
	queue_redraw()


# 本炉当前待烧铜矿数量（供外部查询，如显示/调试）
func get_ore_stock() -> int:
	return _ore_stock


# 烧制进度条 + 「+N」浮动文字（进度条仅在本炉库存有铜矿时显示）
func _draw() -> void:
	var bar_y := -_get_half_height() - 18.0
	if _ore_stock > 0:
		var ratio := clampf(_smelt_timer / _get_smelt_interval(), 0.0, 1.0)
		var bar_w := 96.0
		var bar_h := 10.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.12, 0.12, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), Color(0.95, 0.62, 0.15, 0.95))
	# 烧制完成的「+N」：在进度条上方升起并淡出
	if _floaters.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	for f in _floaters:
		var t: float = float(f["elapsed"]) / FLOATER_DURATION
		var alpha: float = clampf(1.0 - t, 0.0, 1.0)
		var pos := Vector2(float(f["offset_x"]), bar_y - 6.0 - t * FLOATER_RISE + float(f["offset_y"]))
		var w := 120.0
		draw_string(
			font,
			pos + Vector2(-w * 0.5, 0.0),
			String(f["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			w,
			36,
			Color(0.95, 0.25, 0.25, alpha)
		)


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
