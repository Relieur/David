class_name PlayerLife
extends HBoxContainer
var mark_scene:PackedScene=preload("res://lifemark.tscn")
# Called when the node enters the scene tree for the first time.
func set_life(life:int):
	life=clampi(life,0,99)
	var _current_mark=get_child_count()
	if life > _current_mark:
		for _i in range(life - _current_mark):
			spwan_life_mark()
			
	if life < _current_mark:
		for _i in range(_current_mark - life):
			dele_life_mark()

func spwan_life_mark():
	var _mark=mark_scene.instantiate()
	add_child(_mark)
			   # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func dele_life_mark():
	var _child = get_child(0)
	remove_child(_child)
	_child.queue_free()
