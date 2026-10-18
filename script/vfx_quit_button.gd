extends TextureButton

## VFX 退出按钮
## - NormalLayer：默认文字
## - HoverLayer：悬停时显示背景与发光文字（复用按下状态素材）
## - Edge：两种状态共用的右侧边线

const SWEEP_START := 1.2
const SWEEP_END := -0.25

@export var enable_press_sweep: bool = false
@export_range(0.05, 1.0, 0.01) var press_sweep_duration: float = 0.5

@onready var _normal_layer: Control = $NormalLayer
@onready var _hover_layer: Control = $HoverLayer
@onready var _hover_bg: TextureRect = $HoverLayer/HoverBG

var _hovered: bool = false
var _sweep_material: ShaderMaterial
var _sweep_tween: Tween


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	_sweep_material = _hover_bg.material as ShaderMaterial
	_refresh_visual()


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_visual()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_visual()


func _on_button_down() -> void:
	if not enable_press_sweep or _sweep_material == null:
		return
	_play_press_sweep()


func _play_press_sweep() -> void:
	if _sweep_tween != null and _sweep_tween.is_valid():
		_sweep_tween.kill()
	_sweep_material.set_shader_parameter("sweep_progress", SWEEP_START)
	_sweep_tween = create_tween()
	_sweep_tween.tween_property(
		_sweep_material, "shader_parameter/sweep_progress", SWEEP_END, press_sweep_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _refresh_visual() -> void:
	_normal_layer.visible = not _hovered
	_hover_layer.visible = _hovered
