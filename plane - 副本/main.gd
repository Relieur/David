extends Node2D
signal take_damage

@onready var character_body_2d: Ship = $CharacterBody2D
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var h_box_container: PlayerLife = $CanvasLayer/HBoxContainer
@onready var endlayer: CanvasLayer = $Endlayer
@onready var score_label: Label = $Endlayer/scoreLabel
@onready var shoot_sfx: AudioStreamPlayer2D = $CharacterBody2D/ShootSFX
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var bullet_pool: Node2D = $BulletPool




var score:int=0
var life:int=0
# Called when the node enters the scene tree for the first time.



func _ready() -> void:
	
	GameSystem.on_pickup_item.connect(on_pickup_item)
	GameSystem.on_kill_enemy.connect(on_kill_enemy)
	GameSystem.on_player_die.connect(on_player_die)
	GameSystem.on_player_shoot.connect(on_player_shoot)
	score=0
	life=3
	canvas_layer.set_score(score)
	h_box_container.set_life(life)





# Called every frame. 'delta' is the elapsed time since the previous frame.

func on_pickup_item():
	print("pickup")
	score+=1000
	on_update_score()
	canvas_layer.set_score(score)
	

func on_kill_enemy():
	score+=500
	on_update_score()
	canvas_layer.set_score(score)
	audio_stream_player_2d.play()
	
func on_update_score():
	var _level=score/2000
	print(_level)
	character_body_2d.set_fire_level(_level)
	
func on_player_die():
	life-=1
	h_box_container.set_life(life)
	if life<=0:
		character_body_2d.kill()
		audio_stream_player_2d.play()
		endlayer.visible=true
	score_label.text="Score:"+str(score)
	
func on_player_shoot(shoot_pos:Vector2):
	var _bullet=bullet_pool.get_obj()
	_bullet.global_position=shoot_pos

func _on_restart_button_pressed() -> void:
	get_tree().call_deferred("reload_current_scene")# Replace with function body.

func play_sfx():
	shoot_sfx.play()
