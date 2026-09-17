extends Node2D
@onready var spawner_makers: Node2D = $SpawnerMakers
var enemy_scene:PackedScene=preload("res://enemy.tscn")
var pickup_scene:PackedScene=preload("res://pickup.tscn")
@onready var timer_pickup: Timer = $TimerPickup


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spawn()
	reset_pickup_time()
	
func spawn():
	var _enemy=enemy_scene.instantiate()
	add_child(_enemy)
	_enemy.global_position=get_spwan_position()

# Called every frame. 'delta' is the elapsed time since the previous frame.

func make_pickup():
	var _pickup=pickup_scene.instantiate()
	add_child(_pickup)
	_pickup.global_position=get_spwan_position()
	
	
func reset_pickup_time():
	var _wait_time=randf_range(3,5)
	timer_pickup.start(_wait_time)
	
	
func get_spwan_position():
	var _arr=spawner_makers.get_children()
	return (_arr.pick_random() as Marker2D).position



func _on_timer_timeout() -> void:
	spawn() # Replace with function body.


func _on_timer_pickup_timeout() -> void:
	make_pickup()
	reset_pickup_time()
