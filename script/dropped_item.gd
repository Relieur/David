extends Area2D
class_name DroppedItem

@export var item_type:String ="copper"
@export var amount :int=1

@onready var sprite_2d: Sprite2D = $Sprite2D
var _dragging:bool=false
var _drag_offset:Vector2=Vector2.ZERO


func _ready() -> void:
	input_pickable=true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
		set_process(false)
	
#点击
func _on_input_event(_viewport:Node,event:InputEvent,_shape_idx:int)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_start_drag()

#全局输入
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()


#开始拖拽
func _start_drag()->void:
	_dragging=true
	_drag_offset=get_global_mouse_position() - global_position
	z_index=100
	input_pickable=false
	set_process(true)
	
	var tween:=create_tween()
	tween.tween_property(self,"scale",Vector2(1.3,1.3),0.1)

#拖拽跟随
func _process(delta: float) -> void:
	if _dragging:
		global_position=get_global_mouse_position() -_drag_offset


#拖拽结束
func _end_drag()->void:
	_dragging=false
	z_index=10
	input_pickable=true
	set_process(false)
	
	
	var tween:=create_tween()
	tween.tween_property(self,"scale",Vector2.ONE,0.1)
	
	#检测仓库
	var warehouse:=get_tree().get_first_node_in_group("warehouse")
	if warehouse and warehouse.is_point_inside(global_position):
		_deposit()
	


func _deposit()->void:
	GameManager.add_item(item_type,amount)
	queue_free()
