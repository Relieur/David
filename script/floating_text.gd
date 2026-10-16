extends Node2D
class_name FloatingText

# 一次性浮动文字：从指定世界坐标向上飘一段距离并淡出，播完自动回收。
#
# 用法（调用方先 add_child 再 setup）：
#   var ft := FLOATING_TEXT_SCENE.instantiate() as FloatingText
#   get_tree().current_scene.add_child(ft)
#   ft.setup("+1", Color(0.45, 0.95, 0.42), world_pos)
#
# top_level = true：用世界坐标，不跟随父节点变换。
# 这样既可以直接挂在场景根（不随角色被移除而消失），也不会被父节点的缩放动画影响。

const RISE := 34.0          # 上飘距离（像素）
const DURATION := 0.9       # 存活时长（秒）
const LABEL_W := 130.0
const LABEL_H := 62.0
const FONT_SIZE := 48

var _label: Label = null


func _ready() -> void:
	top_level = true         # 世界坐标：机器人移动也不会把字拖走
	z_index = 20             # 始终画在角色 / 建筑之上
	set_process(false)       # 纯 tween 驱动，不需要逐帧回调


# text: 显示内容；color: 字色；world_pos: 生成位置（世界坐标）
func setup(text: String, color: Color, world_pos: Vector2) -> void:
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", color)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 不拦截鼠标：飘字出现时不能挡住点击机器人 / 矿石
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size = Vector2(LABEL_W, LABEL_H)
	_label.position = Vector2(-LABEL_W * 0.5, -LABEL_H * 0.5)
	add_child(_label)

	# top_level 下 position 就是世界坐标
	position = world_pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", world_pos + Vector2(0.0, -RISE), DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_label, "modulate:a", 0.0, DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	queue_free()
