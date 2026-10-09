extends Control



@onready var open_button: Button = $OpenButton
@onready var full_panel: Control = $FullPanel
@onready var tech_list: VBoxContainer = $FullPanel/Center/Panel/VBox/Scroll/TechList
@onready var close_button: Button = $FullPanel/Center/Panel/VBox/CloseButton
const ITEM_NAMES:={
	"copper":"矿",
}


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_apply_fullscreen_layout()
	full_panel.visible=false
	open_button.pressed.connect(_open)
	close_button.pressed.connect(_close)
	GameManager.inventory_changed.connect(_on_data_changed)
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_TAB:
			if full_panel.visible:
				_close()
			else:
				_open()
		elif event.keycode==KEY_ESCAPE and full_panel.visible:
			_close()


func _unhandled_input(event: InputEvent) -> void:
	if not full_panel.visible:
		return
	# 面板打开时消费滚轮事件，避免下层相机同步缩放（ScrollContainer 已先处理）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()

#打开
func _open()->void:
	full_panel.visible=true
	_refresh()

func _close()->void:
	full_panel.visible=false


func _on_data_changed(_arg=null)->void:
	_refresh()

func _on_tech_unlocked(_tech_id:String)->void:
	_refresh()

func _refresh()->void:
	for child in tech_list.get_children():
		child.queue_free()
	# 已开放的分类（其余分类待策划定稿后再开放）
	const OPEN_CATEGORIES := ["能力升级", "资源点升级"]
	for category in GameManager.CATEGORY_ORDER:
		if category not in OPEN_CATEGORIES:
			continue
		var techs_in_cat: Array[String] = []
		for tech_id in GameManager.TECHS:
			if GameManager.TECHS[tech_id].get("category", "") == category:
				techs_in_cat.append(tech_id)
		if techs_in_cat.is_empty():
			continue
		tech_list.add_child(_make_category_title(category))
		for tech_id in techs_in_cat:
			tech_list.add_child(_make_tech_row(tech_id))


func _make_category_title(category: String) -> Control:
	var title := Label.new()
	title.text = "—— %s ——" % category
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color(0.95, 0.85, 0.4, 1.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sep := HSeparator.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(title)
	box.add_child(sep)
	return box


func _make_tech_row(tech_id:String)->Control:
	var tech:Dictionary=GameManager.TECHS[tech_id]
	var row:=HBoxContainer.new()
	row.custom_minimum_size=Vector2(0,0)
	row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",12)
	#描述左侧
	var info:=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.custom_minimum_size=Vector2(200,0)

	var name_label:=Label.new()
	name_label.text=tech["name"]
	name_label.add_theme_font_size_override("font_size",18)
	info.add_child(name_label)

	var desc_label:=Label.new()
	desc_label.text=tech["desc"]
	desc_label.add_theme_font_size_override("font_size",12)
	desc_label.modulate=Color(0.7,0.7,0.7,1.0)
	desc_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	desc_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)

	# 前置依赖可视化：列出尚未满足的前置科技
	var missing_prereq: Array[String] = []
	for pre in tech.get("prereq", []):
		if not GameManager.is_tech_unlocked(pre):
			missing_prereq.append(GameManager.TECHS.get(pre, {}).get("name", pre))
	if not missing_prereq.is_empty():
		var pre_label := Label.new()
		pre_label.text = "需先解锁：" + "、".join(missing_prereq)
		pre_label.add_theme_font_size_override("font_size", 11)
		pre_label.modulate = Color(0.9, 0.5, 0.5, 1.0)
		pre_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pre_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		info.add_child(pre_label)

	row.add_child(info)

	#需求
	var cost_label:=Label.new()
	var parts:Array[String]=[]
	for item_type in tech["cost"]:
		var display:String=ITEM_NAMES.get(item_type,item_type)
		var need:int = tech["cost"][item_type]
		var have:int =GameManager.get_count(item_type)
		parts.append("%s %d/%d"%[display,have,need])
	cost_label.text="  ".join(parts)
	cost_label.custom_minimum_size=Vector2(110,0)
	cost_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	row.add_child(cost_label)


	#按钮
	var btn:=Button.new()
	btn.custom_minimum_size=Vector2(120,44)
	if GameManager.is_tech_unlocked(tech_id):
		btn.text="已解锁"
		btn.disabled=true
	elif not missing_prereq.is_empty():
		btn.text="前置未满足"
		btn.disabled=true
	elif GameManager.can_unlock_tech(tech_id):
		btn.text="解锁"
		btn.disabled=false
		btn.pressed.connect(func ():
				GameManager.unlock_tech(tech_id))
	else:
		btn.text="资源不足"
		btn.disabled=true
	row.add_child(btn)
	return row

func _apply_fullscreen_layout() -> void:
	# 根节点铺满
	_set_full_rect(self)
	full_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# FullPanel 铺满
	_set_full_rect(full_panel)

	# Dim 铺满
	var dim := full_panel.get_node_or_null("Dim")
	if dim:
		_set_full_rect(dim)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.color = Color(0, 0, 0, 0)

	# Center 铺满
	var center := full_panel.get_node_or_null("Center")
	if center:
		_set_full_rect(center)


# 把任意 Control 设成全屏铺满
func _set_full_rect(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
