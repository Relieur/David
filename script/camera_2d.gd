extends Camera2D
class_name CameraController

@export var move_speed:float=800.0
@export var smooth:float=10.0
@export var zoom_level:=1.0
@export var limit_to_map:bool=true


@export var zoom_step:float=0.1
@export var zoom_min:float=0.5
@export var zoom_max:float=4.0

var _target_position:Vector2
var _home_position:Vector2
var map_size_px:Vector2=Vector2(2048,2048)
var viewport_size:Vector2=Vector2(1280,720)
var _flying: bool = false
var _is_panning: bool = false
var _pan_last_screen: Vector2 = Vector2.ZERO


func _ready() -> void:
	make_current()
	zoom=Vector2(zoom_level,zoom_level)
	viewport_size=get_viewport_rect().size
	_target_position=position
	_home_position=position
	

func _process(delta: float) -> void:
	if _flying:
		return

	# 中键拖动地图：优先处理，跳过键盘移动
	if _is_panning:
		var mouse_screen := get_viewport().get_mouse_position()
		var delta_screen := mouse_screen - _pan_last_screen
		_pan_last_screen = mouse_screen
		# 屏幕像素差 / zoom = 世界像素差；拖动方向与相机移动方向相反
		var delta_world := delta_screen / zoom.x
		_target_position -= delta_world
		_clamp_target()
		position = _target_position
		return

	var dir :=Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		dir.x+=1
	if Input.is_action_pressed("move_left"):
		dir.x-=1
	if Input.is_action_pressed("move_down"):
		dir.y+=1
	if Input.is_action_pressed("move_up"):
		dir.y-=1
	if dir !=Vector2.ZERO:
		dir =dir.normalized()
		_target_position+= dir * move_speed * delta

	_clamp_target()
	position=position.lerp(_target_position,smooth*delta)


func _clamp_target() -> void:
	if not limit_to_map:
		return
	var half_view:=viewport_size *0.5 / zoom
	_target_position.x=clamp(_target_position.x,half_view.x,map_size_px.x-half_view.x)
	_target_position.y=clamp(_target_position.y,half_view.y,map_size_px.y-half_view.y)

func set_target(pos: Vector2) -> void:
	position = pos
	_target_position = pos
	_home_position=pos
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode==KEY_SPACE and event.pressed and not event.echo:
		_target_position=_home_position


func fly_to(target: Vector2, duration: float = 0.6) -> void:
	# 如果已经在飞，先停止
	if _flying:
		return
	_flying = true

	# 同时更新内部目标位置，避免飞完之后又被 lerp 拉回去
	_target_position = target

	var start := position
	var tween := create_tween()
	tween.tween_method(
		func(t): position = start.lerp(target, t),
		0.0, 1.0, duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	position = target
	_flying = false


#缩放与中键拖动
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_panning = true
				_pan_last_screen = get_viewport().get_mouse_position()
			else:
				_is_panning = false
			get_viewport().set_input_as_handled()
		elif event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_mouse(1.0 + zoom_step)
			elif  event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_mouse(1.0 - zoom_step)

func _zoom_at_mouse(factor:float)->void:
	var old_zoom:=zoom.x
	var new_zoom: float=clamp(old_zoom*factor,zoom_min,zoom_max)
	if is_equal_approx(old_zoom,new_zoom):
		return
	var mouse_world:=get_global_mouse_position()
	zoom=Vector2(new_zoom,new_zoom)
	var mouse_world_after:=get_global_mouse_position()
	var diff:=mouse_world-mouse_world_after
	position+=diff
	_target_position+=diff
