extends Control

## 开始菜单主控脚本（对照 UI 设计稿）
## - 三个主按钮：开始游戏（切换主场景）/ 游戏设置（打开设置面板）/ 退出游戏
## - 设置面板：音量滑块实时写入 GameManager；画质 / 显示模式在“保存”时生效
## - 交互约定与 script/hud_ui.gd 保持一致：ESC 关闭设置面板

## 游戏主场景。project.godot 的 main_scene 当前指向 wolrd.tscn，
## 想从菜单启动的话，把 main_scene 改成 "res://scene/start.tscn" 即可。
const WORLD_SCENE := "res://scene/wolrd.tscn"

## 恢复默认的预设值
const DEFAULT_MUSIC_VOL := 0.7
const DEFAULT_SFX_VOL := 0.85

## 画质档位：0=低 1=中 2=高。
## 当前是 2D 项目、暂无渲染分级，这里只记录选择，
## 可作为以后接入渲染缩放等画质选项的扩展点。
var _quality: int = 2

@onready var _settings_root: Control = $SettingsRoot
@onready var _music_slider: HSlider = $SettingsRoot/Panel/VBox/MusicRow/Slider
@onready var _music_value: Label = $SettingsRoot/Panel/VBox/MusicRow/Value
@onready var _sfx_slider: HSlider = $SettingsRoot/Panel/VBox/SfxRow/Slider
@onready var _sfx_value: Label = $SettingsRoot/Panel/VBox/SfxRow/Value
@onready var _quality_seg: Array[Button] = [
	$SettingsRoot/Panel/VBox/QualityRow/Seg/Low,
	$SettingsRoot/Panel/VBox/QualityRow/Seg/Mid,
	$SettingsRoot/Panel/VBox/QualityRow/Seg/High,
]
@onready var _display_seg: Array[Button] = [
	$SettingsRoot/Panel/VBox/DisplayRow/Seg/Windowed,
	$SettingsRoot/Panel/VBox/DisplayRow/Seg/Fullscreen,
]


func _ready() -> void:
	# ---- 主菜单按钮 ----
	$Menu/Column/Buttons/StartButton.pressed.connect(_on_start_pressed)
	$Menu/Column/Buttons/SettingsButton.pressed.connect(_on_settings_pressed)
	$Menu/Column/Buttons/QuitButton.pressed.connect(_on_quit_pressed)
	# ---- 设置面板：关闭 / 保存 / 恢复默认 ----
	$SettingsRoot/Panel/VBox/Header/CloseButton.pressed.connect(_close_settings)
	$SettingsRoot/Panel/VBox/Footer/SaveButton.pressed.connect(_on_save_pressed)
	$SettingsRoot/Panel/VBox/Footer/ResetButton.pressed.connect(_on_reset_pressed)
	# ---- 音量滑块：拖动实时生效 ----
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_music_slider.value = GameManager.get_ambient_volume()
	_sfx_slider.value = GameManager.get_sfx_volume()
	_update_volume_label(_music_value, _music_slider.value)
	_update_volume_label(_sfx_value, _sfx_slider.value)
	# ---- 分段控件：选中态样式由代码刷新（原因见 _refresh_seg_styles） ----
	for btn: Button in _quality_seg + _display_seg:
		btn.toggled.connect(_refresh_seg_styles)
	# 显示模式按当前实际窗口状态回显，覆盖场景里默认按下的“全屏”
	var mode: int = DisplayServer.window_get_mode()
	var fullscreen_now: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_display_seg[1].button_pressed = fullscreen_now
	_display_seg[0].button_pressed = not fullscreen_now
	_refresh_seg_styles(false)
	_settings_root.visible = false


# ==================== 主菜单按钮 ====================
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings_pressed() -> void:
	_settings_root.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func _close_settings() -> void:
	_settings_root.visible = false


# ==================== 保存 / 恢复默认 ====================
func _on_save_pressed() -> void:
	# 显示模式立即生效（窗口 / 全屏切换）
	if _display_seg[1].button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# 记录画质档位（2D 项目暂只记录，可扩展为渲染缩放等）
	for i: int in _quality_seg.size():
		if _quality_seg[i].button_pressed:
			_quality = i
	_close_settings()


func _on_reset_pressed() -> void:
	# 恢复音量与画质默认值；显示模式保持当前选择不动，
	# 避免“恢复默认”造成窗口突然跳变
	_music_slider.value = DEFAULT_MUSIC_VOL
	_sfx_slider.value = DEFAULT_SFX_VOL
	_quality_seg[2].button_pressed = true
	_close_settings()


# ==================== 音量 ====================
func _on_music_volume_changed(value: float) -> void:
	GameManager.set_ambient_volume(value)
	_update_volume_label(_music_value, value)


func _on_sfx_volume_changed(value: float) -> void:
	GameManager.set_sfx_volume(value)
	_update_volume_label(_sfx_value, value)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)


# ==================== 分段控件选中态 ====================
# Button 没有“选中态”样式槽：normal / hover / pressed 里的 pressed 只在
# 按下的瞬间显示，松开就回到 normal，表达不了“已选中”。
# 所以这里在选中时把 normal 槽替换为主题里的 seg/pressed 样式（亮绿填充），
# 取消选中时移除 override；悬停态仍由主题的 hover 槽负责。
# （ButtonGroup 保证同组互斥，切换时 toggled 信号会带刷新全部按钮。）
func _refresh_seg_styles(_toggled_on: bool) -> void:
	for btn: Button in _quality_seg + _display_seg:
		if btn.button_pressed:
			btn.add_theme_stylebox_override("normal", get_theme_stylebox("pressed", "seg"))
		else:
			btn.remove_theme_stylebox_override("normal")


# ==================== 键盘 ====================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _settings_root.visible:
			_close_settings()
			get_viewport().set_input_as_handled()
