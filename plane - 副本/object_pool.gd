class_name ObjectPool
extends Node2D

@export var object_scene:PackedScene
@export var POOL_SIZE=50

var _available_objs:Array[Node]=[]

func _ready() -> void:
	_pool_size_up()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func get_obj()->Node:
	var _obj: Node=null
	if _available_objs.is_empty():
		_pool_size_up()
		
	_obj=_available_objs.pop_back()
	_obj.set_active(true)
	return _obj

func return_obj(obj:Node):
	if obj in _available_objs:
		return
	obj.set_active(false)
	_available_objs.append(obj)
 
func _pool_size_up():
	for i in POOL_SIZE:
		var _new_obj=object_scene.instantiate()
		add_child(_new_obj)
		_new_obj.set_active(false)
		_available_objs.append(_new_obj)
	
	
