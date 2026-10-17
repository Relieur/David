extends Control

# 机器人悬浮信息面板：鼠标悬停在机器人上时，跟随机器人显示状态、背包

const OFFSET := Vector2(24, -130)   # 相对机器人屏幕位置的偏移（右上，整体浮在机器人上方）
const TEXT_REFRESH_INTERVAL := 0.1  # 文本刷新间隔（位置每帧跟随，文本降频刷新）

var _robot: Robot = null
var _tween: Tween
var _text_timer: float = 0.0

@onready var _state_label: Label = $Margin/VBox/StateLabel
@onready var _backpack_label: Label = $Margin/VBox/BackpackLabel



func _ready() -> void:
	add_to_group("robot_popup")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)   # 未悬停时不需要逐帧跟随
	reset_size()


# 悬停进入：绑定机器人并播放出现动画
func show_for(robot: Robot) -> void:
	if robot == null or not is_instance_valid(robot):
		return
	_robot = robot
	_text_timer = TEXT_REFRESH_INTERVAL
	_refresh_text()
	reset_size()
	visible = true
	set_process(true)
	_play_appear()


# 悬停离开：仅在仍绑定该机器人时隐藏
func hide_popup(robot: Robot = null) -> void:
	if robot != null and _robot != robot:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_robot = null
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _robot == null or not is_instance_valid(_robot):
		hide_popup()
		return
	# 文本降频刷新（位置每帧跟随即可）
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = TEXT_REFRESH_INTERVAL
		_refresh_text()
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * _robot.global_position
	global_position = screen_pos + OFFSET


func _refresh_text() -> void:
	if _robot == null:
		return
	_set_label_text(_state_label, _robot.get_state_text())
	_set_label_text(_backpack_label, _robot.get_backpack_text())


# 仅当文本真正变化时才赋值并重排，避免每帧触发控件布局重算
func _set_label_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
		reset_size()


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
