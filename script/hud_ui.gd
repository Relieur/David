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

var _res_cache: Dictionary = {}    # item_type -> 上次显示的数值
var _gear_tween: Tween
var _ui_hidden: bool = false

# 隐藏/显示 UI 时一起切换的 HUD 元素（不含 HideUIButton 本身）
var _hud_elements: Array[CanvasItem] = []


func _ready() -> void:
	$GearButton.pressed.connect(_toggle_settings)
	$LabButton.pressed.connect(_on_lab_pressed)
	$GearButton.mouse_entered.connect(_on_gear_hover)
	$GearButton.mouse_exited.connect(_on_gear_unhover)
	_gear_button.pivot_offset = _gear_button.size * 0.5
	$SettingsRoot/Panel/VBox/Buttons/ResumeButton.pressed.connect(_close_settings)
	$SettingsRoot/Panel/VBox/Buttons/MenuButton.pressed.connect(_on_menu_pressed)
	$SettingsRoot/Panel/VBox/Buttons/QuitButton.pressed.connect(_on_quit_pressed)
	$HideUIButton.pressed.connect(_toggle_hide_ui)
	# 音量滑块
	$SettingsRoot/Panel/VBox/AmbientVol/Slider.value_changed.connect(_on_ambient_volume_changed)
	$SettingsRoot/Panel/VBox/SfxVol/Slider.value_changed.connect(_on_sfx_volume_changed)
	$SettingsRoot/Panel/VBox/AmbientVol/Slider.value = GameManager.get_ambient_volume()
	$SettingsRoot/Panel/VBox/SfxVol/Slider.value = GameManager.get_sfx_volume()
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
	]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_toggle_hide_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _settings_root.visible:
			_close_settings()
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


func _process(_delta: float) -> void:
	# 炉内铜矿没有变化信号，靠每帧轮询；数值没变就不重写 text
	var changed := false
	for item_type in _res_cache:
		var amount := _get_amount(item_type)
		if _res_cache.get(item_type, -1) == amount:
			continue
		_res_cache[item_type] = amount
		changed = true
	if changed:
		_refresh_resources(GameManager.inventory)


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


func _format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_type in cost:
		var display_name: String = ITEM_NAMES.get(item_type, item_type)
		parts.append("%d %s" % [int(cost[item_type]), display_name])
	return "、".join(parts)


# ==================== 设置面板 ====================
func _toggle_settings() -> void:
	_settings_root.visible = not _settings_root.visible


func _on_ambient_volume_changed(value: float) -> void:
	GameManager.set_ambient_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	GameManager.set_sfx_volume(value)


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
	_settings_root.visible = false


# LAB 按钮 → 开/关研究所面板（开关逻辑在 ResearchLabUI 自己身上）
func _on_lab_pressed() -> void:
	var lab := get_node_or_null("../ResearchLabUI")
	if lab != null and lab.has_method("toggle"):
		lab.toggle()


func _on_menu_pressed() -> void:
	_close_settings()
	get_tree().change_scene_to_file(START_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
