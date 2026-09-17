extends Node


# Called when the node enters the scene tree for the first time.
signal on_pickup_item 
signal on_kill_enemy
signal on_player_die

# Called every frame. 'delta' is the elapsed time since the previous frame.
signal on_player_shoot(shoot_pos:Vector2)
