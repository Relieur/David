extends Area2D
class_name  WareHouse
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

#仓库

func _ready() -> void:
	add_to_group("warehouse")

func is_point_inside(world_pos:Vector2)->bool:
	var local:=to_local(world_pos)
	var shape:=collision_shape_2d.shape
	
	if shape is RectangleShape2D:
		var rect:=shape as RectangleShape2D
		var half : Vector2= rect.size*0.5
		return abs(local.x)<=half.x and abs(local.y) <=half.y 
	elif shape is CircleShape2D:
		var circle=shape as CircleShape2D
		return local.length()<=shape.radius
	return false
