extends Area2D
class_name Ore

signal mined(ore_type :String ,amount :int)

@export var ore_type :String ="copper"
@export var amount :int =1
@export var  mine_time: float =0.3


@onready var sprite_2d: Sprite2D = $Sprite2D


var is_mining:bool=false
var can_mine:bool=true
var _original_modulate:Color

#生命周期
func _ready() -> void:
	input_pickable=true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	if sprite_2d:
		_original_modulate=sprite_2d.modulate

#点击
func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed() and event.button_index==MOUSE_BUTTON_LEFT:
		mine()
		
#采集
func mine()->void:
	if is_mining or not can_mine:
		return
	is_mining=true
	can_mine=false
	if sprite_2d:
		var tween : = create_tween()
		tween.tween_property(sprite_2d,"modulate", Color(0.4, 0.4, 0.4, 1.0),mine_time*0.4)
		
	await  get_tree().create_timer(mine_time).timeout
	mined.emit(ore_type,amount)
	is_mining=false
	_start_cooldown()
#冷却
func _start_cooldown()->void:
	await get_tree().create_timer(mine_time).timeout
	if sprite_2d:
		var tween:= create_tween()
		tween.tween_property(sprite_2d,"modulate",_original_modulate,mine_time*0.4)
		can_mine=true
