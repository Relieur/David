extends Control

## 开始菜单主控脚本（对照 StartScene 美术资源与设计稿）
## - 四个主按钮：开始游戏 / 继续游戏（读档）/ 游戏设置 / 退出游戏
## - 已有存档时点「开始游戏」弹出确认框：「若选择开始游戏会覆盖旧存档 是否继续?」
## - 按钮交互：四个主按钮统一使用 VFX 按钮的悬停 Shader 与按下扫光
## - 存档：进游戏后由 wolrd 场景负责自动保存（定时 + 关窗退出时），本界面只负责读档入口

const WORLD_SCENE := "res://scene/wolrd.tscn"
const TRANSITION_DELAY := 0.3
const TRANSITION_FADE_TIME := 0.2

## 确认框 是/否 贴图：[normal, hover]
const YES_TEXTURES := [
	preload("res://art/StartScene/UI_Btn_Yes_Normal.png"),
	preload("res://art/StartScene/UI_Btn_Yes_Hover.png"),
]
const NO_TEXTURES := [
	preload("res://art/StartScene/UI_Btn_No_Normal.png"),
	preload("res://art/StartScene/UI_Btn_No_Hover.png"),
]

## 鼠标视差：默认顺序为 BG、Title、Start、Continue、Settings、Quit。
## 正数跟随鼠标移动，负数反向移动；绝对值越大，图层越“近”。
@export_group("Parallax")
@export var parallax_layer_nodes: Array[Control] = []
@export var parallax_strengths: Array[float] = [-8.0, 10.0, 16.0, 20.0, 24.0, 28.0]
@export_range(1.0, 20.0, 0.1) var parallax_smoothing: float = 8.0

@onready var _confirm_root: Control = $ConfirmRoot
@onready var _settings_root: Control = $SettingsRoot
@onready var _sfx_slider: HSlider = $SettingsRoot/BG/SfxSlider
@onready var _master_slider: HSlider = $SettingsRoot/BG/MasterSlider
@onready var _music_slider: HSlider = $SettingsRoot/BG/MusicSlider
@onready var _fullscreen_check: CheckBox = $SettingsRoot/BG/FullscreenCheck
@onready var _fade_overlay: ColorRect = $FadeOverlay
@onready var _bg: TextureRect = $BG

var _transitioning: bool = false
var _parallax_base_positions: Array[Vector2] = []
var _parallax_current := Vector2.ZERO


func _ready() -> void:
	# 开始界面背景音乐
	GameManager.play_bgm(GameManager.BGM_START)
	# ---- 主菜单按钮：统一的 VFX 悬停/按下效果 ----
	$Buttons/StartButton.pressed.connect(_on_start_pressed)
	$Buttons/ContinueButton.pressed.connect(_on_continue_pressed)
	$Buttons/SettingsButton.pressed.connect(_on_settings_pressed)
	$Buttons/QuitButton.pressed.connect(_on_quit_pressed)
	# 没有存档时「继续游戏」置灰不可点
	if not GameManager.has_save():
		var continue_btn: TextureButton = $Buttons/ContinueButton
		continue_btn.disabled = true
		continue_btn.modulate = Color(1, 1, 1, 0.45)
	# ---- 覆盖存档确认框 ----
	_setup_center_button($ConfirmRoot/Window/YesButton, YES_TEXTURES[0], YES_TEXTURES[1])
	_setup_center_button($ConfirmRoot/Window/NoButton, NO_TEXTURES[0], NO_TEXTURES[1])
	$ConfirmRoot/Window/YesButton.pressed.connect(_on_confirm_yes)
	$ConfirmRoot/Window/NoButton.pressed.connect(_on_confirm_no)
	_confirm_root.visible = false
	# ---- 设置面板：关闭 + 三条音量滑条实时生效 ----
	$SettingsRoot/BG/CloseButton.pressed.connect(_close_settings)
	$SettingsRoot/BG/QuitButton.pressed.connect(_on_quit_pressed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	# 滑条填充条（FillImg）宽度跟随当前值（轨道/填充均为 SettingsPanel 素材）
	for slider: HSlider in [_sfx_slider, _master_slider, _music_slider]:
		slider.value_changed.connect(func(v: float) -> void: _update_fill(slider, v))
		_update_fill(slider, slider.value)
	_sfx_slider.value = GameManager.get_sfx_volume()
	_master_slider.value = GameManager.get_master_volume()
	_music_slider.value = GameManager.get_ambient_volume()
	# 全屏复选框：回显当前窗口模式
	var mode: int = DisplayServer.window_get_mode()
	_fullscreen_check.button_pressed = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_settings_root.visible = false
	_setup_parallax()


# 直接关闭窗口时也保存音量设置
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameManager.save_options()


# ==================== 主菜单按钮 ====================
func _on_start_pressed() -> void:
	if _transitioning:
		return
	if GameManager.has_save():
		_confirm_root.visible = true
	else:
		_begin_new_game()


func _on_continue_pressed() -> void:
	if _transitioning:
		return
	# 读取存档并进入游戏（存档进度在 wolrd._ready 里按 restore_mode 重建）
	if GameManager.load_game():
		_transitioning = true
		await _fade_out()
		get_tree().change_scene_to_file(WORLD_SCENE)
	else:
		# 存档可能已被外部删除：刷新置灰状态
		var continue_btn: TextureButton = $Buttons/ContinueButton
		continue_btn.disabled = true
		continue_btn.modulate = Color(1, 1, 1, 0.45)


func _on_settings_pressed() -> void:
	_settings_root.visible = true


# ==================== 鼠标视差 ====================
func _setup_parallax() -> void:
	if parallax_layer_nodes.is_empty():
		var default_layers: Array[Control] = [
			$BG,
			$Title,
			$Buttons/StartButton,
			$Buttons/ContinueButton,
			$Buttons/SettingsButton,
			$Buttons/QuitButton,
		]
		parallax_layer_nodes = default_layers
	if parallax_strengths.size() < parallax_layer_nodes.size():
		parallax_strengths.resize(parallax_layer_nodes.size())
	_update_bg_pivot()
	_capture_parallax_base_positions()
	resized.connect(_on_start_resized)


func _process(delta: float) -> void:
	if parallax_layer_nodes.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var mouse := get_viewport().get_mouse_position()
	var target := (mouse / viewport_size - Vector2(0.5, 0.5)) * 2.0
	target = target.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	_parallax_current = _parallax_current.lerp(
		target, 1.0 - exp(-parallax_smoothing * delta)
	)
	for i in parallax_layer_nodes.size():
		var layer := parallax_layer_nodes[i]
		if layer == null:
			continue
		layer.position = _parallax_base_positions[i] \
			+ _parallax_current * _get_parallax_strength(i)


func _on_start_resized() -> void:
	# 等锚点布局完成后再重记基准位置，避免窗口尺寸变化后产生累计偏移
	call_deferred("_refresh_parallax_layout")


func _refresh_parallax_layout() -> void:
	_update_bg_pivot()
	_capture_parallax_base_positions()
	_parallax_current = Vector2.ZERO
	for i in parallax_layer_nodes.size():
		var layer := parallax_layer_nodes[i]
		if layer != null:
			layer.position = _parallax_base_positions[i]


func _update_bg_pivot() -> void:
	var bg_size := _bg.size
	if bg_size == Vector2.ZERO:
		bg_size = get_viewport_rect().size
	_bg.pivot_offset = bg_size * 0.5


func _capture_parallax_base_positions() -> void:
	_parallax_base_positions.clear()
	for i in parallax_layer_nodes.size():
		var layer := parallax_layer_nodes[i]
		if layer == null:
			_parallax_base_positions.append(Vector2.ZERO)
			continue
		# 窗口变化时先扣掉当前视差位移，记录真正的布局基准
		_parallax_base_positions.append(
			layer.position - _parallax_current * _get_parallax_strength(i)
		)


func _get_parallax_strength(index: int) -> float:
	return parallax_strengths[index] if index < parallax_strengths.size() else 0.0


func _on_quit_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	GameManager.save_options()
	await _fade_out()
	get_tree().quit()


func _fade_out() -> void:
	# 播放 Shader sweep 后等待片刻，再用 0.2 秒渐黑
	_fade_overlay.modulate.a = 0.0
	_fade_overlay.visible = true
	await get_tree().create_timer(TRANSITION_DELAY).timeout
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "modulate:a", 1.0, TRANSITION_FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished


func _close_settings() -> void:
	GameManager.save_options()
	_settings_root.visible = false


# ==================== 覆盖存档确认框 ====================
func _begin_new_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	# 开始新游戏：删除旧存档并清空进度，避免中途退出后“继续游戏”回到上一局
	GameManager.delete_save()
	GameManager.reset_progress()
	await _fade_out()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_confirm_yes() -> void:
	_confirm_root.visible = false
	_begin_new_game()


func _on_confirm_no() -> void:
	_confirm_root.visible = false


# ==================== 音量 ====================
# 滑条填充条宽度 = 滑条宽 × 当前值（FillImg 贴在滑条内、左对齐）
func _update_fill(slider: HSlider, _value: float = -1.0) -> void:
	var fill: TextureRect = slider.get_node("FillImg")
	fill.offset_right = 469.0 * slider.value


func _on_sfx_volume_changed(value: float) -> void:
	GameManager.set_sfx_volume(value)


func _on_master_volume_changed(value: float) -> void:
	GameManager.set_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	GameManager.set_ambient_volume(value)


# 全屏 / 窗口切换
func _on_fullscreen_toggled(fullscreen: bool) -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# 确认框小按钮（是/否）：热区固定，子节点 Img 在热区内居中，hover 原尺寸放大
func _setup_center_button(btn: TextureButton, tex_normal: Texture2D, tex_hover: Texture2D) -> void:
	var img: TextureRect = btn.get_node("Img")
	img.texture = tex_normal
	_center_img(img, tex_normal)
	btn.mouse_entered.connect(func() -> void:
		if btn.disabled:
			return
		img.texture = tex_hover
		_center_img(img, tex_hover))
	btn.mouse_exited.connect(func() -> void:
		img.texture = tex_normal
		_center_img(img, tex_normal))


func _center_img(img: TextureRect, tex: Texture2D) -> void:
	var w := int(tex.get_width())
	var h := int(tex.get_height())
	img.offset_left = -w / 2
	img.offset_right = w / 2 + w % 2
	img.offset_top = -h / 2
	img.offset_bottom = h / 2 + h % 2


# ==================== 键盘 ====================
func _input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _settings_root.visible:
				_close_settings()
				get_viewport().set_input_as_handled()
			elif _confirm_root.visible:
				_confirm_root.visible = false
				get_viewport().set_input_as_handled()
