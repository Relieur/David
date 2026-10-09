extends Area2D
class_name Ore

signal mined(ore_type :String ,amount :int)

@export var ore_type :String ="copper"
@export var amount :int =1
@export var  mine_time: float =0.3
@export var clicks_needed:int=3  #所需点击的次数



@onready var sprite_2d: Sprite2D = $Sprite2D


var is_mining:bool=false
var can_mine:bool=true
var _original_modulate:Color
var _click_count:int=0  #已经点击次数
var _color_tween: Tween
var _robot_progress:int=0  #机器人采矿进度
var _robot_busy:bool=false  #机器人采矿冷却中

#生命周期
func _ready() -> void:
	add_to_group("ore")
	input_pickable = false  #取消玩家点击挖矿，只有机器人能采
	if sprite_2d:
		_original_modulate=sprite_2d.modulate
#点击

#点击
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed() and event.button_index==MOUSE_BUTTON_LEFT:
		_on_click()

func _on_click()->void:
	if is_mining or not can_mine:
		return
	_click_count+=1
	_update_darkness()
	if _click_count>=clicks_needed:
		mine()


#依次变暗
func _update_darkness()->void:
	if not sprite_2d:
		return
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	var progress:=float(_click_count) / float(clicks_needed)
	var target:=_original_modulate.lerp(Color(0.4,0.4,0.4,1.0),progress)
	_color_tween=create_tween()
	_color_tween.tween_property(sprite_2d,"modulate",target,0.1)



#采集
func mine()->void:
	if is_mining or not can_mine:
		return
	is_mining=true
	can_mine=false
	#变暗
	if sprite_2d:
		if _color_tween and _color_tween.is_valid():
			_color_tween.kill()
		_color_tween=create_tween()
		_color_tween.tween_property(sprite_2d,"modulate", Color(0.4, 0.4, 0.4, 1.0),mine_time*0.4) 
		
	await  get_tree().create_timer(mine_time).timeout
	mined.emit(ore_type,amount)
	is_mining=false
	_start_cooldown()




#冷却
func _start_cooldown()->void:
	await get_tree().create_timer(mine_time).timeout
	if sprite_2d:
		if _color_tween and _color_tween.is_valid():
			_color_tween.kill()
		_color_tween= create_tween()
		_color_tween.tween_property(sprite_2d,"modulate",_original_modulate,mine_time*0.4)
		await  _color_tween.finished
		_click_count=0
		can_mine=true

#机器人交互：每1s调用一次，返回true表示采集成功获得矿物
func robot_interact() -> bool:
	if _robot_busy or is_mining or not can_mine:
		return false
	_robot_progress += 1
	#视觉变暗
	if sprite_2d:
		if _color_tween and _color_tween.is_valid():
			_color_tween.kill()
		var progress := float(_robot_progress) / float(clicks_needed)
		var target := _original_modulate.lerp(Color(0.4, 0.4, 0.4, 1.0), progress)
		_color_tween = create_tween()
		_color_tween.tween_property(sprite_2d, "modulate", target, 0.1)
	if _robot_progress >= clicks_needed:
		_robot_progress = 0
		_robot_busy = true
		_robot_cooldown()
		return true
	return false

#机器人采矿冷却
func _robot_cooldown() -> void:
	await get_tree().create_timer(mine_time).timeout
	if sprite_2d:
		if _color_tween and _color_tween.is_valid():
			_color_tween.kill()
		_color_tween = create_tween()
		_color_tween.tween_property(sprite_2d, "modulate", _original_modulate, mine_time * 0.4)
		await _color_tween.finished
	_robot_busy = false
