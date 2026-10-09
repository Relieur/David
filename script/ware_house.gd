extends Area2D
class_name  WareHouse#仓库

const  TILE_SIZE=64

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D



func _ready() -> void:
	add_to_group("warehouse")
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_align_to_grid()


# 点击仓库：若已选中机器人，则手动指挥它返回卸货
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("command_return"):
			robot.command_return()

#对齐
func _align_to_grid()->void:
	position.x=round(position.x / TILE_SIZE )*TILE_SIZE
	position.y=round(position.y / TILE_SIZE )*TILE_SIZE
	if collision_shape_2d.shape is RectangleShape2D:
		var rect:=collision_shape_2d.shape as RectangleShape2D
		rect.size.x=round(rect.size.x / TILE_SIZE)*TILE_SIZE
		rect.size.y=round(rect.size.y / TILE_SIZE)*TILE_SIZE



func set_center_to(world_pos:Vector2)->void:
	position =world_pos
	_align_to_grid()



#仓库判断
func is_point_inside(world_pos:Vector2)->bool:
	var local:=to_local(world_pos)
	var shape:=collision_shape_2d.shape
	if shape is RectangleShape2D:
		var rect:=shape as RectangleShape2D
		var half : Vector2= rect.size*0.5
		return abs(local.x)<=half.x and abs(local.y) <=half.y
	elif shape is CircleShape2D:
		var circle=shape as CircleShape2D
		return local.length()<=circle.radius
	return false

#机器人入库：将背包内容全部存入，返回存入数量
func robot_deposit(robot) -> int:
	var amount: int = robot.backpack
	if amount > 0:
		GameManager.add_item(robot.carry_type, amount)
		robot.backpack = 0
	return amount
