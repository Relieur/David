class_name Enemy
extends Area2D
@export var SPEED:float=-100
@export var LIFE_MAX:float=3
var life:float
func _ready()->void:
	life=LIFE_MAX
# Called when the node enters the scene tree for the first time.
func _physics_process(delta: float) -> void:
	global_position.x += SPEED*delta
	
func take_damage():
	
	if life<=0:
		return
	life-=1
	if life<=0:
		die()
		score()
func die():
	queue_free()
	
	print("die")
	
func score():
	GameSystem.on_kill_enemy.emit()


func _on_ship_entered(body: Node2D) -> void:
	(body as Ship).take_damage()
	die()
