class_name  PoolableArea2D
extends Area2D

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

var is_active:bool = true

# Called when the node enters the scene tree for the first time.
func set_active(active:bool):
	if active:
		visible=true
		set_physics_process(true)
		set_process(true)
		collision_shape_2d.set_deferred("disabled",false)
	else:
		visible=false
		set_physics_process(false)
		set_process(false)
		collision_shape_2d.set_deferred("disabled",true)
	
