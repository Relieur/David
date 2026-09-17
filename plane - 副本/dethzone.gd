extends Node2D


# Called when the node enters the scene tree for the first time.




func _on_area_entered(area: Area2D) -> void:
	(area as Enemy).die()
	 # Replace with function body.
