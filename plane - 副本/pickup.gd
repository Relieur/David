extends Area2D
@export var SPEED:float=-500

# Called when the node enters the scene tree for the first time.
func _physics_process(delta: float) -> void:
	global_position.x += SPEED*delta

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _on_body_entered(body:Node2D) -> void:
	if body.is_in_group("Ship"):
		print(body.name)
		queue_free()
		GameSystem.on_pickup_item.emit()
