class_name Ship
extends CharacterBody2D

@export var SHOOT_COOL_DOWN:float=100
@export var SPEED:float = 900.0
@export var SLOW_DOWN:float = 10000.0
@export var JUMP_VELOCITY = 800.0
@export var fire_level_list:Array[Firelevel]
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var shoot_sfx: AudioStreamPlayer2D = $ShootSFX
var bullet_scene:PackedScene=preload("res://scenes/bullet.tscn")
var is_dead:bool=false
var last_shoot_time:float=0
var fire_level:int=0
var current_level_file:Firelevel


var bullet_scenes:PackedScene=preload("res://scenes/bullet.tscn")

func _ready() -> void:
	current_level_file=fire_level_list[0]

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# Add the gravity.
	var direction=Input.get_vector("move_left","move_right","move_up","move_down")
	if direction:
		velocity=direction* SPEED
	else:
		velocity=velocity.move_toward(Vector2.ZERO,SLOW_DOWN*delta)

	move_and_slide()
	position_control()
	handel_shoot()

func kill():
	is_dead=true
	sprite_2d.visible=false
	collision_shape_2d.set_deferred("disabled",true)

func position_control():
	var screen_size=get_viewport_rect().size
	global_position=global_position.clamp(Vector2.ZERO,screen_size)
	

	
func handel_shoot():
	
	if Input.is_action_pressed("shoot"):
		var _time_now=Time.get_ticks_msec()
		if _time_now - last_shoot_time > current_level_file.bullet_cooldown:
		 #发射子弹
			spawn_some_bullets(global_position,current_level_file.bullet_split,current_level_file.bullet_count)
			last_shoot_time = _time_now
			shoot_sfx.play()
		else:
			pass

func spawn_some_bullets(center_pos:Vector2,split_size:float,count:int):
	for i in range(count):
		var _pos= center_pos
		_pos.y += split_size*(i - ((count-1)/2.0))
		GameSystem.on_player_shoot.emit(_pos)
	
		
	

	
func take_damage():
	GameSystem.on_player_die.emit()
		
func set_fire_level(level:int):
	fire_level=clampi(level,0,len(fire_level_list)-1)
	current_level_file=fire_level_list[fire_level]

	
func get_pickup():
	print("pickup!")
	
