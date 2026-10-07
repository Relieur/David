extends Camera2D
class_name CameraController

@export var move_speed:float=800.0
@export var smooth:float=10.0
@export var zoom_level:=1.0
@export var limit_to_map:bool=true

var _target_position:Vector2
var map_size_px:Vector2=Vector2(2048,2048)
var viewport_size:Vector2=Vector2(1280,720)



func _ready() -> void:
	make_current()
	_target_position=position
	viewport_size=get_viewport_rect().size
	

func _process(delta: float) -> void:
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
	
	if limit_to_map:
		var half_view:=viewport_size *0.5 / zoom
		_target_position.x=clamp(_target_position.x,half_view.x,map_size_px.x-half_view.x)
		_target_position.y=clamp(_target_position.y,half_view.y,map_size_px.y-half_view.y)
	position=position.lerp(_target_position,smooth*delta)

func set_target(pos: Vector2) -> void:
	position = pos
	_target_position = pos
