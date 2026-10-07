extends Area2D
class_name  WareHouse#仓库

const  TILE_SIZE=16

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D



func _ready() -> void:
	add_to_group("warehouse")
	_align_to_grid()

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
