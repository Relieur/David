extends Control

# 机器人悬浮信息面板：鼠标悬停在机器人上时，跟随机器人显示状态、背包、坐标点记忆

const OFFSET := Vector2(24, -130)   # 相对机器人屏幕位置的偏移（右上，整体浮在机器人上方）

var _robot: Robot = null
var _tween: Tween

@onready var _state_label: Label = $Margin/VBox/StateLabel
@onready var _backpack_label: Label = $Margin/VBox/BackpackLabel
@onready var _coords_label: Label = $Margin/VBox/CoordsLabel



func _ready() -> void:
	add_to_group("robot_popup")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	reset_size()


# 悬停进入：绑定机器人并播放出现动画
func show_for(robot: Robot) -> void:
	if robot == null or not is_instance_valid(robot):
		return
	_robot = robot
	_refresh_text()
	reset_size()
	visible = true
	_play_appear()


# 悬停离开：仅在仍绑定该机器人时隐藏
func hide_popup(robot: Robot = null) -> void:
	if robot != null and _robot != robot:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_robot = null
	visible = false


func _process(_delta: float) -> void:
	if _robot == null or not is_instance_valid(_robot):
		hide_popup()
		return
	_refresh_text()
	reset_size()
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * _robot.global_position
	global_position = screen_pos + OFFSET


func _refresh_text() -> void:
	if _robot == null:
		return
	_state_label.text = _robot.get_state_text()
	_backpack_label.text = _robot.get_backpack_text()
	var mem := _robot.get_memory_text()
	_coords_label.text = mem
	_coords_label.visible = not mem.is_empty()


# 出现小动画：从中心放大 + 淡入
func _play_appear() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.18)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.12)
