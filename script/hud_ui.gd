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

@onready var _settings_root: Control = $SettingsRoot
@onready var _resources_label: Label = $TopBar/Resources
@onready var _goal_body: Label = $LabGoalPanel/Body
@onready var _stage_progress: TextureProgressBar = $StageProgress/Fill
@onready var _gear_button: TextureButton = $GearButton
@onready var _hide_ui_button: Button = $HideUIButton
@onready var _key_guide_button: Button = $KeyGuideButton
@onready var _sustain_hint: TextureRect = $SustainHint
@onready var _sustain_hint_label: Label = $SustainHint/Label
@onready var _sfx_slider: HSlider = $SettingsRoot/BG/SfxSlider
@onready var _master_slider: HSlider = $SettingsRoot/BG/MasterSlider
@onready var _music_slider: HSlider = $SettingsRoot/BG/MusicSlider
@onready var _fullscreen_check: CheckBox = $SettingsRoot/BG/FullscreenCheck

var _res_cache: Dictionary = {}    # item_type -> 上次显示的数值
var _gear_tween: Tween
var _ui_hidden: bool = false

# ==================== 按键指南 ====================
const KEY_GUIDE_ROWS := [
	["W / A / S / D", "移动镜头"],
	["空格", "镜头回到初始位置"],
	["鼠标中键拖动", "平移地图"],
	["鼠标滚轮", "缩放地图"],
	["鼠标左键 · 机器人", "选中机器人"],
	["鼠标左键 · 矿点", "已选中机器人时派它去挖矿；未选中时手动挖一块"],
	["鼠标左键 · 精炼炉", "已选中机器人时派它去该炉卸货；未选中时鼓风加温"],
	["鼠标左键 · 掉落物", "让掉落物自动飞回精炼炉"],
	["鼠标右键", "取消选中机器人"],
	["TAB", "打开 / 关闭研究所"],
	["ESC", "打开 / 关闭设置（研究所打开时先关闭研究所）"],
	["R", "隐藏 / 显示界面"],
]
const KEY_GUIDE_COLOR := Color(0.682353, 0.819608, 0.309804)      # 荧光绿：按键名
const KEY_GUIDE_TEXT_COLOR := Color(0.86, 0.89, 0.80)            # 浅色：说明文字
var _key_guide_root: Control = null

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
	$KeyGuideButton.pressed.connect(_toggle_key_guide)
	_build_key_guide()
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
	_refresh_resources(GameManager.inventory)
	_refresh_goal()

	# 收集需要随「隐藏 UI」一起切换的顶层 HUD 元素
	_hud_elements = [
		$TopFade,
		$TopBar,
		$RightPanel,
		$LabGoalPanel,
		$StageProgress,
		$LabButton,
		$GearButton,
		$KeyGuideButton,
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
			# 按键指南打开时优先关闭它
			if _key_guide_root != null and _key_guide_root.visible:
				_close_key_guide()
				get_viewport().set_input_as_handled()
				return
			# ESC：设置面板已开则关闭，否则打开
			if _settings_root.visible:
				_close_settings()
			else:
				_toggle_settings()
			get_viewport().set_input_as_handled()


# ==================== 顶栏资源显示 ====================
func _on_inventory_changed(inventory: Dictionary) -> void:
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

	# 单行显示，用 " | " 分隔（无空隙）
	var parts: PackedStringArray = []
	for item_type in order:
		var amount := _get_amount(item_type)
		_res_cache[item_type] = amount
		parts.append("%s x %d" % [_get_display_name(item_type), amount])
	_resources_label.text = " | ".join(parts)


func _get_amount(item_type: String) -> int:
	if item_type == "copper":
		return GameManager.get_furnace_ore_total()
	return GameManager.get_count(item_type)


func _get_display_name(item_type: String) -> String:
	if NAME_OVERRIDES.has(item_type):
		return NAME_OVERRIDES[item_type]
	return ITEM_NAMES.get(item_type, item_type)


# 炉内铜矿没有变化信号，靠低频轮询；0.25 秒一次足够显示，避免每帧扫分组
const POLL_INTERVAL := 0.25
var _poll_timer: float = 0.0


func _process(delta: float) -> void:
	# 冷却按帧平滑递减（提示队列的动画由 tween 自己驱动）
	if _sustain_cooldown > 0.0:
		_sustain_cooldown -= delta
	if _ui_hidden:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	# 炉内铜矿没有变化信号，靠轮询；数值没变就不重写 text
	var changed := false
	for item_type in _res_cache:
		var amount := _get_amount(item_type)
		if _res_cache.get(item_type, -1) == amount:
			continue
		_res_cache[item_type] = amount
		changed = true
	if changed:
		_refresh_resources(GameManager.inventory)
	# 可持续提示：冷却结束且满足条件时触发一次
	if _sustain_cooldown <= 0.0 and _should_show_sustain_hint():
		_sustain_cooldown = SUSTAIN_COOLDOWN
		show_hint(SUSTAIN_TEXT)


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


# ==================== 按键指南 ====================
func _toggle_key_guide() -> void:
	if _key_guide_root == null:
		return
	_key_guide_root.visible = not _key_guide_root.visible
	if _key_guide_root.visible:
		_settings_root.visible = false


func _close_key_guide() -> void:
	if _key_guide_root != null:
		_key_guide_root.visible = false


# 构建按键指南弹窗（按键列表改 KEY_GUIDE_ROWS 即可）
func _build_key_guide() -> void:
	_key_guide_root = Control.new()
	_key_guide_root.visible = false
	_key_guide_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_key_guide_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key_guide_root)

	# 半透明遮罩：拦截背后点击，点击遮罩也可关闭
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_key_guide_dim_input)
	_key_guide_root.add_child(dim)

	# 居中面板
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -500.0
	panel.offset_top = -330.0
	panel.offset_right = 500.0
	panel.offset_bottom = 330.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.03, 0.95)
	style.border_color = Color(KEY_GUIDE_COLOR, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_key_guide_root.add_child(panel)

	var title := Label.new()
	title.text = "按键指南"
	title.anchor_right = 1.0
	title.offset_top = 18.0
	title.offset_bottom = 62.0
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", KEY_GUIDE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	# 关闭按钮
	var close_btn := TextureButton.new()
	close_btn.texture_normal = load("res://art/SettingsPanel/UI_Btn_Close.png")
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_SCALE
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -60.0
	close_btn.offset_top = 14.0
	close_btn.offset_right = -20.0
	close_btn.offset_bottom = 54.0
	close_btn.pressed.connect(_close_key_guide)
	panel.add_child(close_btn)

	# 按键行
	var rows := VBoxContainer.new()
	rows.anchor_right = 1.0
	rows.anchor_bottom = 1.0
	rows.offset_left = 46.0
	rows.offset_top = 84.0
	rows.offset_right = -46.0
	rows.offset_bottom = -28.0
	rows.add_theme_constant_override("separation", 10)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)

	for row_data in KEY_GUIDE_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var key_label := Label.new()
		key_label.text = String(row_data[0])
		key_label.custom_minimum_size = Vector2(250.0, 0.0)
		key_label.add_theme_font_size_override("font_size", 22)
		key_label.add_theme_color_override("font_color", KEY_GUIDE_COLOR)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(key_label)

		var desc := Label.new()
		desc.text = String(row_data[1])
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.add_theme_font_size_override("font_size", 21)
		desc.add_theme_color_override("font_color", KEY_GUIDE_TEXT_COLOR)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(desc)

		rows.add_child(row)


func _on_key_guide_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_key_guide()
		get_viewport().set_input_as_handled()


# ==================== 设置面板 ====================
func _toggle_settings() -> void:
	_settings_root.visible = not _settings_root.visible
	if _settings_root.visible:
		_close_key_guide()


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
	# 隐藏时同时收起设置 / 按键指南面板，避免残留半透明遮罩
	if _ui_hidden:
		_settings_root.visible = false
		_close_key_guide()
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
