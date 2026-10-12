extends Control

# 研究所 UI（仅样式，暂不绑定逻辑）
# 展示研究所阶段 0~5，当前阶段高亮，下一阶段升级入口预留（消耗待定）

const STAGE_NAMES := ["研究所阶段0", "研究所阶段1", "研究所阶段2", "研究所阶段3", "研究所阶段4", "研究所阶段5"]
# 阶段颜色（与科技树配色一致：0红、1橙、2绿）
const STAGE_COLORS := [
	Color(0.95, 0.45, 0.45, 1.0),
	Color(0.95, 0.70, 0.35, 1.0),
	Color(0.45, 0.85, 0.55, 1.0),
	Color(0.45, 0.70, 0.95, 1.0),
	Color(0.70, 0.45, 0.95, 1.0),
	Color(0.95, 0.95, 0.95, 1.0),
]
# 当前阶段（样式占位，后续接入真实数据）
var current_stage: int = 0

@onready var open_button: Button = $OpenButton
@onready var full_panel: Control = $FullPanel
@onready var stage_list: VBoxContainer = $FullPanel/Center/Panel/VBox/Scroll/StageList
@onready var close_button: Button = $FullPanel/Center/Panel/VBox/CloseButton


func _ready() -> void:
	_apply_fullscreen_layout()
	full_panel.visible = false
	open_button.pressed.connect(_open)
	close_button.pressed.connect(_close)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if full_panel.visible:
				_close()
			else:
				_open()
		elif event.keycode == KEY_ESCAPE and full_panel.visible:
			_close()


func _unhandled_input(event: InputEvent) -> void:
	if not full_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()


func _open() -> void:
	full_panel.visible = true
	_refresh()


func _close() -> void:
	full_panel.visible = false


func _refresh() -> void:
	for child in stage_list.get_children():
		child.queue_free()
	for i in STAGE_NAMES.size():
		stage_list.add_child(_make_stage_row(i))


# 单个阶段行：左侧阶段名（带颜色），右侧状态/升级按钮
func _make_stage_row(stage: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(260, 0)

	var name_label := Label.new()
	name_label.text = STAGE_NAMES[stage]
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.modulate = STAGE_COLORS[stage]
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = "解锁该阶段及以下的科技升级权限"
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)

	row.add_child(info)

	# 状态 / 升级按钮（占位，不绑定逻辑）
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 44)
	if stage < current_stage:
		btn.text = "已达成"
		btn.disabled = true
	elif stage == current_stage:
		btn.text = "当前阶段"
		btn.disabled = true
	elif stage == current_stage + 1:
		btn.text = "升级（消耗待定）"
		btn.disabled = true
	else:
		btn.text = "阶段未开启"
		btn.disabled = true
	row.add_child(btn)
	return row


func _apply_fullscreen_layout() -> void:
	_set_full_rect(self)
	full_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(full_panel)
	var dim := full_panel.get_node_or_null("Dim")
	if dim:
		_set_full_rect(dim)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.color = Color(0, 0, 0, 0)
	var center := full_panel.get_node_or_null("Center")
	if center:
		_set_full_rect(center)


func _set_full_rect(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
