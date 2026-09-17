extends Area2D

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D


# Called when the node enters the scene tree for the first time.


func _on_area_entered(area: Area2D) -> void:
	if area is bullet:
		area.die()
