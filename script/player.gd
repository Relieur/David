extends RigidBody2D


var speed: float=900

func _ready() -> void:
	pass


func _physics_process(_delta: float) -> void:
	var direction=Vector2.ZERO
	direction.x=Input.get_axis("move_left","move_right")
	direction.y=Input.get_axis("move_up","move_down")
	linear_velocity =direction.normalized()*speed
