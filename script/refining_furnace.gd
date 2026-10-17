extends Area2D
class_name RefiningFurnace   #精炼炉

const TILE_SIZE := 64

const SMELT_INTERVAL_BASE := 2.0      # 基础烧制耗时（秒）
const SMELT_TIME_PER_LEVEL := 0.25    # 「煅烧速度」每级减少的烧制耗时（秒）
const DOUBLE_SMELT_BASE_CHANCE := 0.15  # 「无中生有」触发双倍产出的基础概率
const CRIT_CHANCE_PER_LEVEL := 0.15     # 「暴击率」每级增加的双倍产出概率
const ORES_PER_INGOT := 1             # 每个原矿产出 1 个铜锭
const ORE_TYPE := "copper"            # 输入：铜原矿
const INGOT_TYPE := "copper_ingot"    # 产出：铜锭

const FLOATER_DURATION := 0.9         # 「+N」浮动文字的存在时长（秒）
const FLOATER_RISE := 42.0            # 「+N」浮动文字的上升距离（像素）
const FLOATER_COLOR := Color(0.40, 0.78, 1.0, 1.0)  # 「+N」字色：蓝色（与机器人采矿的绿色 +1 区分）

# 炉体外观：默认待机 / 燃烧中
const SPRITE_IDLE := preload("res://art/Inventory_Idle.png")
const SPRITE_ACTIVE := preload("res://art/Inventory_active.png")

const BURN_FADE_DURATION := 0.18       # 待机 ↔ 燃烧的贴图交叉过渡时长（秒，快速）

# ==================== 炉温：玩家在自动化之后的核心操作点 ====================
# 机器人把矿挖回来后，产出速度由玩家「照料炉火」的水平决定：
# 炉子燃烧时炉温持续下降，炉温越低烧得越慢，玩家点击炉子「鼓风」回温。
# 炉子越多（扩建精炼炉最多 6 个）、烧制科技越高（烧得越快→冷得越快），玩家越忙。
const HEAT_MAX := 100.0            # 满炉温
const HEAT_DECAY := 3.0            # 基准降温速度（每秒），满温约 33 秒烧尽
const HEAT_PER_FAN := 35.0         # 每次鼓风回复的炉温
const FAN_COOLDOWN := 0.35         # 鼓风冷却（秒），防连点瞬满
const HEAT_MIN_EFFICIENCY := 0.4   # 炉温归零时的最低烧制效率（不至于完全停摆）
const HEAT_WARN_RATIO := 0.3       # 低于这个比例时炉温条变红并提示鼓风

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D

var _active_sprite: Sprite2D = null       # 燃烧态贴图（叠在待机图之上，做交叉淡入淡出）
var _burning_particles: CPUParticles2D = null  # 燃烧时的橙色粒子
var _fade_tween: Tween = null            # 贴图过渡 tween

var _smelt_timer: float = 0.0        # 当前铜锭的烧制计时
var _ore_stock: int = 0              # 本炉独立存储的待烧铜矿数量（不与其它炉共享）
var _is_active: bool = true          # 是否已启用（预放置的炉子开局只有名字最小的那个启用）
var _floaters: Array = []            # 烧制完成时「+N」浮动效果列表
var _burning: bool = false           # 本炉是否正在燃烧（用于炉火音效的启停判断）
var _heat: float = HEAT_MAX          # 当前炉温（0~100）
var _fan_cooldown: float = 0.0       # 鼓风冷却计时


func _ready() -> void:
	add_to_group("furnace")
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_align_to_grid()
	_setup_burning_visual()


func is_active() -> bool:
	return _is_active


# 启用 / 停用：停用的炉子隐藏、停止烧制、并退出 "furnace" 分组，
# 这样机器人寻路和掉落物「找最近的炉子」都不会选中它
func set_active(active: bool) -> void:
	_is_active = active
	visible = active
	input_pickable = active
	set_process(active)
	# 停用的炉子同时关掉实体碰撞，否则隐藏的炉子仍会挡住机器人
	var solid := get_node_or_null("SolidBody")
	if solid != null:
		solid.get_node("CollisionShape2D").disabled = not active
	if active:
		if not is_in_group("furnace"):
			add_to_group("furnace")
	else:
		if is_in_group("furnace"):
			remove_from_group("furnace")
		_smelt_timer = 0.0
		# 停用炉子立即退出炉火音效计数（set_process(false) 后 _process 不再运行）
		_set_burning(false)


# 点击精炼炉：若已选中机器人，则手动指挥它前往并卸货到本炉；否则给炉子鼓风加温
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 机器人优先级更高：点在机器人身上时让给机器人选中，本次不鼓风 / 不命令返回
		if Robot.is_point_over_robot(get_global_mouse_position()):
			return
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("command_return"):
			robot.command_return(self)
			# 已经指定目的地，自动取消选中
			GameManager.deselect_robot()
		elif GameManager.is_tech_unlocked("sync_fan"):
			_fan_all()
		else:
			_fan()


# 同步鼓风：解锁「同步鼓风」后，点击一个炉子给所有已启用的炉子一起鼓风。
# 遍历 group "furnace"（已停用的炉子已退出分组，天然只作用于启用中的炉子）。
func _fan_all() -> void:
	for f in get_tree().get_nodes_in_group("furnace"):
		if f is RefiningFurnace:
			f._fan()


# ==================== 炉温 ====================
# 当前炉温比例（0~1），供 UI / 外部查询
func get_heat_ratio() -> float:
	return clampf(_heat / HEAT_MAX, 0.0, 1.0)


# 烧制效率：炉温越高烧得越快，冷却到 0 时降到最低效率
func get_heat_efficiency() -> float:
	return HEAT_MIN_EFFICIENCY + (1.0 - HEAT_MIN_EFFICIENCY) * get_heat_ratio()


# 降温速度：烧得越快（煅烧速度科技越高），炉温掉得也越快，
# 这样后期「炉子多 + 烧得快」时玩家的操作量才跟得上自动化带来的产能。
func _get_heat_decay() -> float:
	var interval := _get_smelt_interval()
	if interval <= 0.0:
		return HEAT_DECAY
	return HEAT_DECAY * (0.6 + 0.4 * SMELT_INTERVAL_BASE / interval)


# 玩家鼓风：回复炉温；冷却中或已停用时无效
func _fan() -> void:
	if not _is_active or _fan_cooldown > 0.0 or _heat >= HEAT_MAX:
		return
	_fan_cooldown = FAN_COOLDOWN
	_heat = minf(HEAT_MAX, _heat + HEAT_PER_FAN)
	_spark_fan()
	queue_redraw()


# 鼓风火星：一次性粒子，播完自动回收
func _spark_fan() -> void:
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(26, 10)
	p.position = Vector2(0, 55)
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, 60)
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 190.0
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))        # 亮黄白
	ramp.add_point(0.4, Color(1.0, 0.6, 0.15, 0.95))     # 橙
	ramp.add_point(1.0, Color(1.0, 0.25, 0.05, 0.0))     # 暗红 → 透明
	p.color_ramp = ramp
	p.z_index = 3
	add_child(p)
	p.emitting = true
	await get_tree().create_timer(p.lifetime + 0.2).timeout
	if is_instance_valid(p):
		p.queue_free()


# 火焰表现跟随炉温：温度高时旺盛明亮，温度低时稀疏黯淡
func _apply_heat_visual() -> void:
	if _burning_particles == null or not _burning_particles.emitting:
		return
	var r := get_heat_ratio()
	_burning_particles.amount = int(round(lerpf(6.0, 26.0, r)))
	_burning_particles.modulate = Color(1, 1, 1, lerpf(0.35, 1.0, r))


# 自动烧制：本炉库存有铜矿时，每「当前烧制耗时」消耗 1 铜矿产出 1 铜锭（铜锭全局共享）
func _process(delta: float) -> void:
	var dirty := _update_floaters(delta)
	if not _is_active:
		if dirty:
			queue_redraw()
		# 停用的炉子若仍在燃烧态，退出炉火音效计数
		_set_burning(false)
		return
	# 鼓风冷却
	if _fan_cooldown > 0.0:
		_fan_cooldown = maxf(0.0, _fan_cooldown - delta)
	var burning := _ore_stock > 0
	_set_burning(burning)
	if _ore_stock > 0:
		# 炉温只在燃烧时下降（空炉不惩罚），并同步火焰表现
		var prev_heat := _heat
		_heat = maxf(0.0, _heat - _get_heat_decay() * delta)
		# 炉温首次降到 0 的瞬间：发出信号（供剧情引导「记得鼓风」等监听）
		if prev_heat > 0.0 and _heat <= 0.0:
			GameManager.furnace_heat_empty.emit(self)
		_apply_heat_visual()
		var interval := _get_smelt_interval()
		# 炉温直接放大烧制进度：温度高=烧得快
		_smelt_timer += delta * get_heat_efficiency()
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
		dirty = true
	elif _smelt_timer != 0.0:
		_smelt_timer = 0.0
		dirty = true
	if dirty:
		queue_redraw()


# 同步炉火音效：本炉燃烧状态发生变化时通知 GameManager 增/减燃烧炉计数
func _set_burning(burning: bool) -> void:
	if _burning == burning:
		return
	_burning = burning
	_apply_burning_visual(burning)
	if burning:
		GameManager.furnace_burning_started()
	else:
		GameManager.furnace_burning_stopped()


# 初始化燃烧态外观：创建叠加的 active 贴图 + 橙色粒子（都在待机图上层）
func _setup_burning_visual() -> void:
	# 燃烧态贴图：叠在待机图之上，初始全透明
	_active_sprite = Sprite2D.new()
	_active_sprite.texture = SPRITE_ACTIVE
	_active_sprite.modulate = Color(1, 1, 1, 0)
	add_child(_active_sprite)

	# 橙红相间粒子：从炉体下半部小范围向上喷发
	_burning_particles = CPUParticles2D.new()
	_burning_particles.amount = 24
	_burning_particles.lifetime = 0.7
	_burning_particles.one_shot = false
	_burning_particles.explosiveness = 0.0
	_burning_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_burning_particles.emission_rect_extents = Vector2(28, 12)
	_burning_particles.position = Vector2(0, 55)
	_burning_particles.direction = Vector2(0, -1)
	_burning_particles.spread = 25.0
	_burning_particles.gravity = Vector2(0, 12)
	_burning_particles.initial_velocity_min = 20.0
	_burning_particles.initial_velocity_max = 55.0
	_burning_particles.scale_amount_min = 3.0
	_burning_particles.scale_amount_max = 6.0
	_burning_particles.color = Color(1.0, 0.55, 0.15, 0.85)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.5, 0.1, 1.0))          # 橙
	ramp.add_point(0.33, Color(1.0, 0.15, 0.05, 0.9))     # 红
	ramp.add_point(0.66, Color(1.0, 0.58, 0.16, 0.6))     # 橙
	ramp.add_point(1.0, Color(1.0, 0.22, 0.02, 0.0))      # 红 → 透明
	_burning_particles.color_ramp = ramp
	_burning_particles.z_index = 2
	_burning_particles.emitting = false
	add_child(_burning_particles)


# 应用燃烧态视觉：交叉淡入淡出贴图 + 开关粒子
func _apply_burning_visual(burning: bool) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	var idle_color := Color(1, 1, 1, 0.0 if burning else 1.0)
	var active_color := Color(1, 1, 1, 1.0 if burning else 0.0)
	_fade_tween.tween_property(sprite_2d, "modulate", idle_color, BURN_FADE_DURATION)
	_fade_tween.parallel().tween_property(_active_sprite, "modulate", active_color, BURN_FADE_DURATION)
	if _burning_particles != null:
		_burning_particles.emitting = burning


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
	# 炉温条：常驻显示在烧制进度条下方，是玩家的主要操作目标
	_draw_heat_bar(bar_y + 12.0)
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
		var w := 140.0
		draw_string(
			font,
			pos + Vector2(-w * 0.5, 0.0),
			String(f["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			w,
			48,
			Color(FLOATER_COLOR.r, FLOATER_COLOR.g, FLOATER_COLOR.b, alpha)
		)


# 炉温条：颜色 绿 → 黄 → 红，过红时在右侧提示「点击鼓风」
func _draw_heat_bar(y: float) -> void:
	var r := get_heat_ratio()
	var bar_w := 96.0
	var bar_h := 8.0
	draw_rect(Rect2(-bar_w * 0.5, y, bar_w, bar_h), Color(0.12, 0.12, 0.12, 0.85))
	draw_rect(Rect2(-bar_w * 0.5, y, bar_w * r, bar_h), _heat_color(r))
	if r <= HEAT_WARN_RATIO:
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(
				font,
				Vector2(bar_w * 0.5 + 6.0, y + bar_h),
				"点击鼓风",
				HORIZONTAL_ALIGNMENT_LEFT,
				120.0,
				18,
				Color(0.95, 0.35, 0.25, 1.0)
			)


# 炉温条颜色：高=绿，中=黄，低=红
func _heat_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.35, 0.9, 0.45, 0.95)
	elif ratio > HEAT_WARN_RATIO:
		return Color(0.95, 0.8, 0.25, 0.95)
	return Color(0.95, 0.35, 0.25, 0.95)


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
