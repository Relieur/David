extends Control

# 研究所 UI：
# - 顶部：6 个阶段进度横向排列（颜色：0红1橙2绿3青4蓝5紫），当前阶段加边框高亮
# - 下方：按 category 分组渲染 20 项科技卡片，每张卡片左侧色条标识所需研究所阶段
# - 双重门槛判定：前置科技至少 1 级 + 研究所阶段 ≥ 该科技所需阶段（沿用 GameManager.can_unlock_tech）

const STAGE_NAMES := ["阶段0", "阶段1", "阶段2", "阶段3", "阶段4", "阶段5"]
const STAGE_COLORS := [
	Color(0.95, 0.45, 0.45, 1.0),   # 0 红
	Color(0.95, 0.70, 0.35, 1.0),   # 1 橙
	Color(0.45, 0.85, 0.55, 1.0),   # 2 绿
	Color(0.45, 0.70, 0.95, 1.0),   # 3 青
	Color(0.70, 0.45, 0.95, 1.0),   # 4 蓝
	Color(0.95, 0.55, 0.95, 1.0),   # 5 紫
]

@onready var open_button: Button = $OpenButton
@onready var full_panel: Control = $FullPanel
@onready var stage_list: VBoxContainer = $FullPanel/Center/Panel/VBox/Scroll/StageList
@onready var close_button: Button = $FullPanel/Center/Panel/VBox/CloseButton


func _ready() -> void:
	_apply_fullscreen_layout()
	full_panel.visible = false
	open_button.pressed.connect(_open)
	close_button.pressed.connect(_close)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if full_panel.visible:
				_close()
			else:
				_open()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and full_panel.visible:
			_close()
			get_viewport().set_input_as_handled()


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


func _on_inventory_changed(_inv: Dictionary) -> void:
	if full_panel.visible:
		_refresh()


func _on_tech_unlocked(_tech_id: String) -> void:
	# 科技解锁会改变前置状态、机器人数量、矿点 reveal，必须刷新整个面板
	if full_panel.visible:
		_refresh()


# ==================== 渲染 ====================
func _refresh() -> void:
	for child in stage_list.get_children():
		child.queue_free()
	# 顶部：阶段进度条
	stage_list.add_child(_make_section_label("研究所阶段"))
	stage_list.add_child(_make_stage_progress())
	stage_list.add_child(_make_separator(10))
	# 下方：按 category 分组的 20 项科技
	for category in GameManager.CATEGORY_ORDER:
		stage_list.add_child(_make_section_label(category))
		var techs: Array = _get_techs_in_category(category)
		for tech_id in techs:
			stage_list.add_child(_make_tech_card(tech_id))
		stage_list.add_child(_make_separator(8))


func _get_techs_in_category(category: String) -> Array:
	var result: Array = []
	for tech_id in GameManager.TECHS:
		var t: Dictionary = GameManager.TECHS[tech_id]
		if t.get("category", "") == category:
			result.append(tech_id)
	return result


func _make_section_label(text: String) -> Control:
	var label := Label.new()
	label.text = "  ▌ " + text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1.0, 0.92, 0.6, 1.0)
	label.custom_minimum_size = Vector2(0, 26)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_separator(sep_h: int) -> Control:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", sep_h)
	sep.custom_minimum_size = Vector2(0, sep_h)
	return sep


# ==================== 阶段进度条 ====================
func _make_stage_progress() -> Control:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)
	for i in STAGE_NAMES.size():
		hbox.add_child(_make_stage_cell(i))
	return hbox


func _make_stage_cell(stage: int) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 78)
	var style := StyleBoxFlat.new()
	style.bg_color = STAGE_COLORS[stage].darkened(0.78)
	style.border_width_bottom = 3
	style.border_color = STAGE_COLORS[stage]
	var current_stage: int = GameManager.lab_stage
	if stage == current_stage:
		# 当前阶段：四边都加边框高亮
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_color = STAGE_COLORS[stage].lightened(0.15)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	cell.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)

	var name_label := Label.new()
	name_label.text = STAGE_NAMES[stage]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.modulate = STAGE_COLORS[stage]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.78, 0.78, 0.78, 1.0)
	vbox.add_child(status_label)

	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_FILL

	if stage < current_stage:
		status_label.text = "已达成"
		btn.text = "✓"
		btn.disabled = true
	elif stage == current_stage:
		status_label.text = "当前阶段"
		btn.text = "●"
		btn.disabled = true
	elif stage == current_stage + 1:
		var cost: Dictionary = GameManager.LAB_STAGE_UPGRADE_COSTS[current_stage]
		status_label.text = "升级 %s" % _format_cost(cost)
		btn.text = "升级"
		btn.disabled = not GameManager.can_upgrade_lab()
		if not btn.disabled:
			btn.pressed.connect(_on_upgrade_pressed)
	else:
		status_label.text = "未开启"
		btn.text = "×"
		btn.disabled = true
	vbox.add_child(btn)
	cell.add_child(vbox)
	return cell


func _format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_type in cost:
		var display_name: String = "铜锭" if item_type == "copper_ingot" else String(item_type)
		parts.append("%d%s" % [int(cost[item_type]), display_name])
	return "/".join(parts)


func _on_upgrade_pressed() -> void:
	if GameManager.upgrade_lab():
		_refresh()


# ==================== 科技卡片 ====================
func _make_tech_card(tech_id: String) -> Control:
	var tech: Dictionary = GameManager.TECHS.get(tech_id, {})
	var next_stage: int = _get_tech_next_lab_stage(tech_id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.16, 1.0)
	style.border_width_left = 4
	style.border_color = STAGE_COLORS[next_stage]
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	# 第1行：名称 + 等级 + 消耗
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = String(tech.get("name", tech_id))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.modulate = STAGE_COLORS[next_stage]
	top_row.add_child(name_label)

	var lv: int = GameManager.get_tech_level(tech_id)
	var max_lv: int = GameManager.get_tech_max_level(tech_id)
	var level_label := Label.new()
	level_label.text = "Lv %d/%d" % [lv, max_lv]
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	top_row.add_child(level_label)

	var cost := GameManager.get_tech_cost(tech_id)
	var cost_label := Label.new()
	cost_label.text = "消耗 %s" % _format_cost(cost)
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.modulate = Color(0.95, 0.85, 0.5, 1.0)
	top_row.add_child(cost_label)
	info.add_child(top_row)

	# 第2行：描述 + 状态原因
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 8)

	var desc_label := Label.new()
	desc_label.text = String(tech.get("desc", ""))
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.modulate = Color(0.62, 0.62, 0.62, 1.0)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bot_row.add_child(desc_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.modulate = Color(0.95, 0.45, 0.45, 1.0)
	bot_row.add_child(status_label)
	info.add_child(bot_row)
	row.add_child(info)

	# 右侧按钮
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(88, 36)
	btn.add_theme_font_size_override("font_size", 12)
	btn.text = "购买"

	var maxed: bool = GameManager.is_tech_unlocked(tech_id)
	if maxed:
		btn.text = "已满级"
		btn.disabled = true
		status_label.text = ""
	elif GameManager.can_unlock_tech(tech_id):
		btn.pressed.connect(_on_tech_purchase.bind(tech_id))
		status_label.text = ""
	else:
		btn.text = "锁定"
		btn.disabled = true
		status_label.text = "▶ %s" % _get_tech_block_reason(tech_id)
	row.add_child(btn)

	card.add_child(row)
	return card


# 获取某科技「下一次升级」所需的研究所阶段（用于卡片标题颜色 / 左色条颜色）
func _get_tech_next_lab_stage(tech_id: String) -> int:
	var tech: Dictionary = GameManager.TECHS.get(tech_id, {})
	if tech.is_empty():
		return 0
	var n: int = GameManager.get_tech_level(tech_id)
	var lab_stages_arr: Array = tech.get("lab_stages", [])
	if lab_stages_arr.size() > 0:
		return int(lab_stages_arr[clampi(n, 0, lab_stages_arr.size() - 1)])
	return int(tech.get("lab_stage", 0))


# 获取科技不可购买的原因（仅用于 UI 文案展示，最终判定以 GameManager.can_unlock_tech 为准）
func _get_tech_block_reason(tech_id: String) -> String:
	var tech: Dictionary = GameManager.TECHS.get(tech_id, {})
	if tech.is_empty():
		return "未知科技"
	if GameManager.is_tech_unlocked(tech_id):
		return "已满级"
	if tech_id == "add_robot":
		var robot_max: int = GameManager.get_robot_max()
		if get_tree().get_nodes_in_group("robots").size() >= robot_max:
			return "机器人已达上限 %d" % robot_max
	for pre in tech.get("prereq", []):
		if GameManager.get_tech_level(String(pre)) < 1:
			var pre_tech: Dictionary = GameManager.TECHS.get(String(pre), {})
			var pre_name: String = String(pre_tech.get("name", String(pre)))
			return "需前置: %s" % pre_name
	var tech_lab_stage: int = _get_tech_next_lab_stage(tech_id)
	if tech_lab_stage > GameManager.lab_stage:
		return "需研究所阶段 %d" % tech_lab_stage
	var cost := GameManager.get_tech_cost(tech_id)
	for item_type in cost:
		if GameManager.get_count(String(item_type)) < int(cost[item_type]):
			return "资源不足"
	return ""


func _on_tech_purchase(tech_id: String) -> void:
	# 兜底再判定一次，防止 UI 状态滞后
	if GameManager.unlock_tech(tech_id):
		# tech_unlocked 信号会触发 _refresh，这里不再重复刷新
		pass
	else:
		_refresh()


# ==================== 全屏布局 ====================
func _apply_fullscreen_layout() -> void:
	_set_full_rect(self)
	full_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_full_rect(full_panel)
	var dim := full_panel.get_node_or_null("Dim")
	if dim:
		_set_full_rect(dim)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.color = Color(0, 0, 0, 0.6)
	var center := full_panel.get_node_or_null("Center")
	if center:
		_set_full_rect(center)
	# 扩大 Panel 以容纳科技卡片
	var panel := full_panel.get_node_or_null("Center/Panel")
	if panel:
		panel.custom_minimum_size = Vector2(920, 700)


func _set_full_rect(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
