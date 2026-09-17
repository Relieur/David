class_name ui_layer
extends CanvasLayer

@onready var label: Label = $Label
var score:int
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	score=0 # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func set_score(score:int):
	label.text="Score:"+str(score)
