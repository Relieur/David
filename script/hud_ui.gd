extends Control
## HUD 框架（对照美术效果图）：
## - 顶部装饰条 UI_HUD_top：中央深色条显示拥有资源（铜锭 / 炉内铜矿等）
## - 右上角「设置」齿轮（UI_HUD_Gear）→ 打开设置面板（纯色深色面板）
## - 右侧装饰面板 UI_HUD_Right + 下方「研究所目标」面板（UI_RightText_BG）
## - 左下角 LAB 按钮（UI_Btn_Lab，用 AtlasTexture 裁掉上方大片透明区）→ 打开研究所
## 素材原始尺寸按 1920×1080 设计，项目设计分辨率已设为 1920×1080，摆放尺寸与素材 1:1

const START_SCENE := "res://scene/start.tscn"
const ITEM_NAMES := {"copper": "铜矿", "copper_ingot": "铜锭"}
const FIXED_ORDER := ["copper_ingot", "copper"]
const NAME_OVERRIDES := {"copper": "铜矿"}
const SEPARATOR := " | "

# 顶栏计数增加时在对应计数下方浮现的「+N」字样
const DELTA_FONT_SIZE := 22                                  # 浮字字号
const DELTA_TIME := 0.9                                      # 浮字存在时长（秒）
const DELTA_DRIFT := 26.0                                    # 浮字向下飘落距离（像素）
const DELTA_COLOR := Color(0.682353, 0.819608, 0.309804)     # 与资源计数同色 #AED14F

@export_group("Top Bar Telemetry")
@export var telemetry_min_interval := 8.0
@export var telemetry_max_interval := 14.0
@export var telemetry_coordinate_limit := 999

@onready var _settings_root: Control = $SettingsRoot
@onready var _resources_label: Label = $TopBar/Resources
@onready var _position_label: Label = $TopBar/posi
@onready var _height_label: Label = $TopBar/high
@onready var _ore_scan_overlay = $TopBar/TextureRect3/ScanOverlay
@onready var _goal_body: Label = $LabGoalPanel/Body
@onready var _stage_progress: TextureProgressBar = $StageProgress/Fill
@onready var _gear_button: TextureButton = $GearButton
@onready var _hide_ui_button: Button = $HideUIButton
@onready var _key_guide_panel: Control = $KeyGuidePanel
@onready var _sustain_hint: TextureRect = $SustainHint
@onready var _sustain_hint_label: Label = $SustainHint/Label
@onready var _sfx_slider: HSlider = $SettingsRoot/BG/SfxSlider
@onready var _master_slider: HSlider = $SettingsRoot/BG/MasterSlider
@onready var _music_slider: HSlider = $SettingsRoot/BG/MusicSlider
@onready var _fullscreen_check: CheckBox = $SettingsRoot/BG/FullscreenCheck

var _res_cache: Dictionary = {}    # item_type -> 上次显示的原始数值（含小数）
var _res_centers: Dictionary = {}  # item_type -> 该条目在顶栏行内的中心 x（供「+N」浮字定位）
var _gear_tween: Tween
var _ui_hidden: bool = false
var _telemetry_timer: float = 0.0
var _telemetry_coordinate := Vector2i.ZERO
var _telemetry_height := 0
var _last_copper_count := 0

# ==================== 上方提示框（队列播放，提示之间不互相抵消） ====================
const SUSTAIN_DURABILITY_THRESHOLD := 0.30   # 耐久低于 30% 触发
const SUSTAIN_FADE_TIME := 1.0               # 淡入 / 淡出各耗时（秒）
const SUSTAIN_HOLD_TIME := 2.0               # 中间保持时长（秒）
const SUSTAIN_COOLDOWN := 60.0               # 两次「可持续」提示的最小间隔（秒）
const SUSTAIN_TEXT := "可持续发展：留点时间让矿点恢复"
var _sustain_cooldown: float = 0.0           # 冷却剩余时间
var _hint_queue: Array[String] = []          # 待播放的提示文本（先进先出）
var _hint_playing: bool = false              # 是否正在播放某条提示
var _hint_tween: Tween                       # 当前提示的渐入渐出动画

# 隐藏/显示 UI 时一起切换的 HUD 元素（不含 HideUIButton 本身）
var _hud_elements: Array[CanvasItem] = []


func _ready() -> void:
	$GearButton.pressed.connect(_toggle_settings)
	$LabButton.pressed.connect(_on_lab_pressed)
	$GearButton.mouse_entered.connect(_on_gear_hover)
	$GearButton.mouse_exited.connect(_on_gear_unhover)
	_gear_button.pivot_offset = _gear_button.size * 0.5
	$SettingsRoot/BG/CloseButton.pressed.connect(_close_settings)
	$SettingsRoot/BG/QuitButton.pressed.connect(_on_quit_pressed)
	$SettingsRoot/BG/QuitButton2.pressed.connect(_on_menu_pressed)
	$HideUIButton.pressed.connect(_toggle_hide_ui)
	# 音量滑块：实时生效 + 填充条跟随
	for slider: HSlider in [_sfx_slider, _master_slider, _music_slider]:
		slider.value_changed.connect(func(v: float) -> void: _update_fill(slider, v))
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value = GameManager.get_sfx_volume()
	_master_slider.value = GameManager.get_master_volume()
	_music_slider.value = GameManager.get_ambient_volume()
	# 全屏复选框：回显当前窗口模式
	var mode: int = DisplayServer.window_get_mode()
	_fullscreen_check.button_pressed = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_settings_root.visible = false
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	GameManager.ore_deposited.connect(_on_ore_deposited)
	_last_copper_count = GameManager.get_count("copper")
	_refresh_resources(GameManager.inventory)
	_refresh_goal()
	_seed_telemetry()

	# 收集需要随「隐藏 UI」一起切换的顶层 HUD 元素
	_hud_elements = [
		$TopFade,
		$TopBar,
		$RightPanel,
		$LabGoalPanel,
		$StageProgress,
		$LabButton,
		$GearButton,
		_key_guide_panel,
	]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_toggle_hide_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# 已被其它面板（如研究所）处理过就不再响应
			if get_viewport().is_input_handled():
				return
			# 研究所打开时 ESC 交给它关闭，不抢事件
			var lab := get_node_or_null("../ResearchLabUI")
			if lab != null and lab.visible:
				return
			# ESC：设置面板已开则关闭，否则打开
			if _settings_root.visible:
				_close_settings()
			else:
				_toggle_settings()
			get_viewport().set_input_as_handled()


# ==================== 顶栏资源显示 ====================
var _res_bounce_tween: Tween = null   # 资源数字跳动特效的 tween（数值连续变化时先杀掉旧的）

func _on_inventory_changed(inventory: Dictionary) -> void:
	var copper_count := int(inventory.get("copper", 0))
	if copper_count > _last_copper_count:
		_ore_scan_overlay.play_increase()
	_last_copper_count = copper_count
	_refresh_resources(inventory)
	_refresh_goal()


func _on_tech_unlocked(_tech_id: String) -> void:
	_refresh_goal()


func _refresh_resources(inventory: Dictionary) -> void:
	# 顺序：固定项（铜锭、铜矿）在前，其余库存物品跟在后面
	var order: Array = []
	for item_type in FIXED_ORDER:
		order.append(item_type)
	for item_type in inventory.keys():
		if not order.has(item_type):
			order.append(item_type)

	# 整行居中排布：先量出各条目文本宽度，算出每条在标签内的中心 x，
	# 好让「+N」浮字对齐到对应计数的正下方
	var font: Font = _resources_label.get_theme_font("font")
	var fs: int = _resources_label.get_theme_font_size("font_size")
	var sep_w: float = font.get_string_size(SEPARATOR, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var texts: PackedStringArray = []
	var widths: Array[float] = []
	var total_w := 0.0
	for item_type in order:
		var seg := _seg_text(item_type)
		texts.append(seg)
		var w: float = font.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total_w += w
	total_w += sep_w * float(maxi(0, order.size() - 1))
	var cursor: float = _resources_label.position.x + _resources_label.size.x * 0.5 - total_w * 0.5

	for i in range(order.size()):
		var item_type: String = String(order[i])
		var center_x: float = cursor + widths[i] * 0.5
		_res_centers[item_type] = center_x
		_set_amount(item_type, _get_amount(item_type), center_x)
		cursor += widths[i] + sep_w
	var new_text := SEPARATOR.join(texts)
	if new_text != _resources_label.text:
		_resources_label.text = new_text
		_play_res_bounce()


# 顶栏数字变化时的跳动特效：先快速放大，再用弹性缓动回弹到原尺寸
func _play_res_bounce() -> void:
	# 以标签中心为缩放轴心，避免跳动时整体位移
	_resources_label.pivot_offset = _resources_label.size * 0.5
	if _res_bounce_tween != null and _res_bounce_tween.is_valid():
		_res_bounce_tween.kill()
	_resources_label.scale = Vector2.ONE
	_res_bounce_tween = create_tween()
	# 峰值由 1.18 降到 1.08：回弹振幅同比减半，跳动更收敛、不再显得抖
	_res_bounce_tween.tween_property(_resources_label, "scale", Vector2(1.08, 1.08), 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_res_bounce_tween.tween_property(_resources_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _get_amount(item_type: String) -> float:
	if item_type == "copper":
		return GameManager.get_furnace_ore_total()
	return float(GameManager.get_count(item_type))


func _get_display_name(item_type: String) -> String:
	if NAME_OVERRIDES.has(item_type):
		return NAME_OVERRIDES[item_type]
	return ITEM_NAMES.get(item_type, item_type)


# 单个条目的显示文本（名称 x 数量）：顶栏数量向下取整显示，小数不展示
func _seg_text(item_type: String) -> String:
	return "%s x %d" % [_get_display_name(item_type), int(floor(_get_amount(item_type)))]


# 更新某条目的计数缓存（存原始数值，含小数）
# 铜矿不在这里弹浮字：炉内铜矿是边进边出的缓冲区，轮询差值会把「投放」和「烧制消耗」混成净增量，
# 所以铜矿浮字改由入炉事件 _on_ore_deposited 触发（只报本次投放量）
func _set_amount(item_type: String, amount: float, center_x: float) -> void:
	var prev: float = float(_res_cache.get(item_type, -1.0))
	_res_cache[item_type] = amount
	if prev >= 0.0 and amount > prev + 0.0001 and item_type == "copper_ingot":
		_spawn_delta_popup(amount - prev, center_x)


# 有矿物投入精炼炉（机器人卸货 / 玩家挖的矿飞入）：按本次投放量弹浮字
func _on_ore_deposited(amount: float) -> void:
	if amount <= 0.0001 or not _res_centers.has("copper"):
		return
	_spawn_delta_popup(amount, float(_res_centers["copper"]))


# 「+N」跳数文本：增量恰好是整数时不带小数位，只要带小数就保留一位（如 +1.3、+3.4）
# 判定用 is_equal_approx（只放过浮点误差级的尘埃），避免真实小数增量被当成整数吞掉
func _format_delta(delta: float) -> String:
	if is_equal_approx(delta, round(delta)):
		return "+%d" % int(round(delta))
	return "+%.1f" % delta


# 在顶栏对应计数下方冒出「+N」浮字：向下飘落并淡出，播完自毁
func _spawn_delta_popup(delta: float, center_x: float) -> void:
	var lbl := Label.new()
	lbl.text = _format_delta(delta)
	lbl.add_theme_font_size_override("font_size", DELTA_FONT_SIZE)
	lbl.add_theme_color_override("font_color", DELTA_COLOR)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 40
	var font: Font = _resources_label.get_theme_font("font")
	var w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, DELTA_FONT_SIZE).x
	var start_y: float = _resources_label.position.y + _resources_label.size.y - 6.0
	lbl.position = Vector2(center_x - w * 0.5, start_y)
	$TopBar.add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", start_y + DELTA_DRIFT, DELTA_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, DELTA_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)


# 炉内铜矿没有变化信号，靠低频轮询；0.25 秒一次足够显示，避免每帧扫分组
const POLL_INTERVAL := 0.25
var _poll_timer: float = 0.0


func _process(delta: float) -> void:
	# 冷却按帧平滑递减（提示队列的动画由 tween 自己驱动）
	if _sustain_cooldown > 0.0:
		_sustain_cooldown -= delta
	_telemetry_timer -= delta
	if _telemetry_timer <= 0.0:
		_update_telemetry()
	if _ui_hidden:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	# 炉内铜矿没有变化信号，靠轮询；数值有变就整体刷新（刷新时按缓存差值冒「+N」浮字）
	for item_type in _res_cache:
		if absf(float(_res_cache.get(item_type, 0.0)) - _get_amount(String(item_type))) > 0.0001:
			_refresh_resources(GameManager.inventory)
			break
	# 可持续提示：冷却结束且满足条件时触发一次
	if _sustain_cooldown <= 0.0 and _should_show_sustain_hint():
		_sustain_cooldown = SUSTAIN_COOLDOWN
		show_hint(SUSTAIN_TEXT)


# ==================== 顶栏坐标 / 高度 ====================
func _seed_telemetry() -> void:
	_telemetry_coordinate = Vector2i(
		randi_range(-240, 240),
		randi_range(-180, 180)
	)
	_telemetry_height = randi_range(120, 320)
	_refresh_telemetry_labels()
	_reset_telemetry_timer()


func _update_telemetry() -> void:
	_telemetry_coordinate.x = clampi(
		_telemetry_coordinate.x + randi_range(-140, 140),
		-telemetry_coordinate_limit,
		telemetry_coordinate_limit
	)
	_telemetry_coordinate.y = clampi(
		_telemetry_coordinate.y + randi_range(-140, 140),
		-telemetry_coordinate_limit,
		telemetry_coordinate_limit
	)
	_telemetry_height = clampi(
		_telemetry_height + randi_range(-45, 45),
		80,
		420
	)
	_refresh_telemetry_labels()
	_reset_telemetry_timer()


func _refresh_telemetry_labels() -> void:
	_position_label.text = "%s,%s" % [
		_signed_int(_telemetry_coordinate.x),
		_signed_int(_telemetry_coordinate.y),
	]
	_height_label.text = "%d" % _telemetry_height


func _signed_int(value: int) -> String:
	return "%s%d" % ["+" if value >= 0 else "-", absi(value)]


func _reset_telemetry_timer() -> void:
	var min_interval := maxf(telemetry_min_interval, 0.1)
	var max_interval := maxf(telemetry_max_interval, min_interval)
	_telemetry_timer = randf_range(min_interval, max_interval)


# ==================== 研究所目标面板 ====================
func _refresh_goal() -> void:
	var lines: PackedStringArray = []
	lines.append("当前阶段：%s" % _stage_name(GameManager.lab_stage))
	var next_stage: int = GameManager.lab_stage + 1
	if next_stage > 5:
		lines.append("目标：已达到最高阶段")
	else:
		var cost: Dictionary = GameManager.LAB_STAGE_UPGRADE_COSTS[GameManager.lab_stage]
		var cost_text := _format_cost(cost)
		lines.append("升级目标：%s → %s" % [_stage_name(GameManager.lab_stage), _stage_name(next_stage)])
		lines.append("所需资源：%s" % cost_text)
	_goal_body.text = "\n".join(lines)
	_refresh_stage_progress()


# 进度条：到达下一个研究所阶段的进度 = 当前铜锭 / 下一阶段升级所需
func _refresh_stage_progress() -> void:
	if GameManager.lab_stage >= GameManager.LAB_STAGE_UPGRADE_COSTS.size():
		_stage_progress.value = 1.0   # 已到最高阶段，常亮满条
		return
	var cost: Dictionary = GameManager.LAB_STAGE_UPGRADE_COSTS[GameManager.lab_stage]
	var need: int = int(cost.get("copper_ingot", 0))
	var have: int = GameManager.get_count("copper_ingot")
	_stage_progress.value = clampf(float(have) / float(need), 0.0, 1.0)


func _stage_name(stage: int) -> String:
	return "阶段%d" % stage


# ==================== 上方提示框 ====================
# 对外接口：把一条提示追加到队列；若当前没有提示在播就立即播，否则排队等前一条播完
func show_hint(text: String) -> void:
	_hint_queue.append(text)
	if not _hint_playing:
		_play_next_hint()


# 驱动「可持续」提示的冷却改由 _process 低频轮询处理（见 _process）


# 判断是否满足「只有一个矿点且耐久低于 30%」
func _should_show_sustain_hint() -> bool:
	var visible_patches: Array = []
	for node in get_tree().get_nodes_in_group("ore_patch"):
		if not is_instance_valid(node) or not node.visible:
			continue
		visible_patches.append(node)
	if visible_patches.size() != 1:
		return false
	var patch: Node2D = visible_patches[0]
	if not patch.has_method("get_durability_ratio"):
		return false
	return patch.get_durability_ratio() < SUSTAIN_DURABILITY_THRESHOLD


# 播放队列里的下一条；队列为空时隐藏提示框
func _play_next_hint() -> void:
	if _hint_queue.is_empty():
		_hint_playing = false
		_sustain_hint.visible = false
		_sustain_hint.modulate.a = 1.0
		_sustain_hint_label.modulate.a = 1.0
		return
	_hint_playing = true
	_sustain_hint_label.text = _hint_queue.pop_front()
	_clear_hint_tween()
	_sustain_hint.visible = true
	_sustain_hint.modulate.a = 0.0
	_sustain_hint_label.modulate.a = 0.0
	_hint_tween = create_tween()
	# 淡入
	_hint_tween.tween_property(_sustain_hint, "modulate:a", 1.0, SUSTAIN_FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hint_tween.parallel().tween_property(_sustain_hint_label, "modulate:a", 1.0, SUSTAIN_FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 保持
	_hint_tween.tween_interval(SUSTAIN_HOLD_TIME)
	# 淡出
	_hint_tween.tween_property(_sustain_hint, "modulate:a", 0.0, SUSTAIN_FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hint_tween.parallel().tween_property(_sustain_hint_label, "modulate:a", 0.0, SUSTAIN_FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hint_tween.finished.connect(_on_hint_finished)


# 一条播完 → 接着播下一条（保证多条提示依次显示、互不抵消）
func _on_hint_finished() -> void:
	_clear_hint_tween()
	_play_next_hint()


func _clear_hint_tween() -> void:
	if _hint_tween != null:
		_hint_tween.kill()
		_hint_tween = null


func _format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_type in cost:
		var display_name: String = ITEM_NAMES.get(item_type, item_type)
		parts.append("%d %s" % [int(cost[item_type]), display_name])
	return "、".join(parts)


# ==================== 设置面板 ====================
func _toggle_settings() -> void:
	_settings_root.visible = not _settings_root.visible


func _on_sfx_volume_changed(value: float) -> void:
	GameManager.set_sfx_volume(value)


func _on_master_volume_changed(value: float) -> void:
	GameManager.set_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	GameManager.set_ambient_volume(value)


# 滑条填充条宽度跟随当前值
func _update_fill(slider: HSlider, _value: float = -1.0) -> void:
	var fill: TextureRect = slider.get_node("FillImg")
	fill.offset_right = 469.0 * slider.value


# 全屏 / 窗口切换
func _on_fullscreen_toggled(fullscreen: bool) -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# 隐藏/显示 HUD：只切换装饰和功能元素，HideUIButton 自身始终可见
func _toggle_hide_ui() -> void:
	_ui_hidden = not _ui_hidden
	for el in _hud_elements:
		el.visible = not _ui_hidden
	# 隐藏时同时收起设置面板，避免残留半透明遮罩
	if _ui_hidden:
		_settings_root.visible = false
		_hide_ui_button.text = "显示UI"
	else:
		_hide_ui_button.text = "隐藏UI"


# 光标悬停齿轮 → 顺时针旋转；移开 → 旋转回正
func _on_gear_hover() -> void:
	_gear_button.pivot_offset = _gear_button.size * 0.5
	if _gear_tween != null:
		_gear_tween.kill()
	_gear_tween = create_tween()
	_gear_tween.tween_property(_gear_button, "rotation", _gear_button.rotation + PI / 2.0, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_gear_unhover() -> void:
	_gear_button.pivot_offset = _gear_button.size * 0.5
	if _gear_tween != null:
		_gear_tween.kill()
	_gear_tween = create_tween()
	# 回正：旋转到最近的一个 2π 整数倍
	var target := snappedf(_gear_button.rotation, TAU)
	if is_equal_approx(_gear_button.rotation, target):
		target += TAU
	_gear_tween.tween_property(_gear_button, "rotation", target, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _close_settings() -> void:
	GameManager.save_options()
	_settings_root.visible = false


# LAB 按钮 → 开/关研究所面板（开关逻辑在 ResearchLabUI 自己身上）
func _on_lab_pressed() -> void:
	var lab := get_node_or_null("../ResearchLabUI")
	if lab != null and lab.has_method("toggle"):
		lab.toggle()


func _on_quit_pressed() -> void:
	# 退出前先存一次，避免 last 60 秒内的进度（含机器人记忆）丢失
	GameManager.save_game()
	GameManager.save_options()
	get_tree().quit()


func _on_menu_pressed() -> void:
	# 回主菜单同样先存档，并清理只在当前场景有效的状态（炉火音效 / 选中 / 面板标记）
	GameManager.save_game()
	GameManager.save_options()
	GameManager.reset_scene_state()
	_close_settings()
	get_tree().change_scene_to_file(START_SCENE)
