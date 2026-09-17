class_name bullet
extends PoolableArea2D
@export var SPEED:float=1000
# Called when the node enters the scene tree for the first time.
func _physics_process(delta: float) -> void:

	global_position.x += SPEED*delta
	if global_position.x>get_viewport_rect().size.x+150.0:
		return_to_pool()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		(get_parent() as ObjectPool).return_obj(self)
		(area as Enemy).take_damage()
	
func die():
	(get_parent() as ObjectPool).return_obj(self)
	
func return_to_pool():
	(get_parent() as ObjectPool).return_obj(self)
	collision_shape_2d.set_deferred("disabled",true)
