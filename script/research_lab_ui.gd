extends Control
# 科技树 UI（节点树版）：
# - 中央：可缩放（滚轮，以鼠标为中心）+ 可拖拽（左键按住平移）的科技节点视图
# - 分支模式：以「添加机器人」为根，能力 / 机器人 / 精炼炉 / 资源点 四条支线向右展开；
#   节点间用 L 形连线，前置未解锁的边挂着 UI_TechTree_Lock 锁图标
# - 悬停节点：整个视图向左让位，右侧滑出 UI_TechTree_DescBG 介绍框（名称 / 消耗 / 描述 / 状态），
#   旁边的 UI_TechTree_UpgradeBtn 双箭头就是购买按钮
# - 左下角：研究所升级入口；右上角：UI_TechTree_Close 关闭按钮
# - TAB 开关面板（保留旧版习惯），ESC 关闭

const ART := "res://art/Techtree/"
const ICON_DIR := ART + "icon/"

const NODE_SIZE := 110.0          # 节点显示尺寸（素材原图 350）
const DESC_W := 488.0             # 介绍框底图原始宽
const DESC_H := 143.0             # 介绍框底图原始高
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.2
const HOVER_DEBOUNCE := 0.08      # 悬停消失防抖（节点间隙移动不闪烁）

# 科技 → 图标文件名（icon/ 下）。未配置图标的科技显示「?」占位节点
const ICONS := {
	"memory_auto": "Intel_AutoPathfinding.png",
	"fallow": "Intel_FallowAwareness.png",
	"priority_sort": "Intel_PriorityQueue.png",
	"density": "Intel_DensitySense.png",
	"info_share": "Intel_Communication.png",
	"resource_swap": "Intel_ResourceTrade.png",
	"reproduce": "Intel_Reproduction.png",
	"regen_speed": "Resource_RegenSpeed.png",
	"ore_durability": "Resource_Durability.png",
	"unlock_more_ores": "Resource_New.png",
	"add_furnace": "Resource_AddSmelter.png",
	"move_speed": "Robot_MoveSpeed.png",
	"mine_speed": "Robot_GatherSpeed.png",
	"mine_yield": "Resource_New.png",
	"mine_crit": "Robot_GatherSpeed.png",
	"fast_mine": "Robot_GatherSpeed.png",
	"robot_count": "Robot_PopCap.png",
	"add_robot": "Robot_RobotCount.png",
	"backpack_capacity": "Intel_PriorityQueue.png",
	"smelt_speed": "Smelter_CalcinationSpeed.png",
	"heat_keep": "Smelter_CalcinationSpeed.png",
	"super_smelter": "Resource_AddSmelter.png",
	"double_smelt": "Smelter_CreateFromVoid.png",
	"smelt_crit": "Smelter_CritRate.png",
	"sync_fan": "Smelter_CalcinationSpeed.png",
}

# 节点在树视图中的位置（ViewRoot 局部坐标）。
# 「添加机器人」的四条支线向上下左右四个方向生长：
#   上 = 能力升级线，下 = 机器人升级线，左 = 精炼炉升级线，右 = 资源点升级线
#   每个方向再沿该方向继续向后生长（前置在前、后置在后）
const POSITIONS := {
	"add_robot": Vector2(0, 0),
	# —— 上：能力升级线 ——（fallow 的后置并列同一排；x=0 留空给 fallow→reproduce 的竖线）
	"memory_auto": Vector2(0, -300),
	"fallow": Vector2(0, -600),
	"priority_sort": Vector2(-270, -900),
	"density": Vector2(-90, -900),
	"info_share": Vector2(90, -900),
	"resource_swap": Vector2(270, -900),
	"reproduce": Vector2(0, -1200),
	# —— 下：机器人升级线 ——
	"move_speed": Vector2(0, 300),
	"backpack_capacity": Vector2(-220, 600),
	"mine_speed": Vector2(0, 600),
	"robot_count": Vector2(220, 600),
	"mine_yield": Vector2(0, 900),
	"mine_crit": Vector2(-220, 900),
	"fast_mine": Vector2(330, 900),
	# —— 左：精炼炉升级线 ——
	"smelt_speed": Vector2(-300, 0),
	"heat_keep": Vector2(-300, 180),
	"super_smelter": Vector2(-600, 180),
	"double_smelt": Vector2(-600, 0),
	"smelt_crit": Vector2(-900, 0),
	"sync_fan": Vector2(-1200, 0),
	# —— 右：资源点升级线 ——
	"regen_speed": Vector2(300, 0),
	"ore_durability": Vector2(600, 180),
	"unlock_more_ores": Vector2(600, -180),
	"add_furnace": Vector2(900, -180),
}

# 配色：只使用两种字色 ——
#   #494948 深灰：用在亮底图上（介绍框 DescBG）
#   #AED14F 荧光绿：用在深色 / 半透明压暗背景上（研究所面板、节点小字、连线、占位节点）
const COLOR_ON_DESC := Color(0.286275, 0.286275, 0.282353)   # 494948
const COLOR_ON_DARK := Color(0.682353, 0.819608, 0.309804)   # AED14F
const LINE_UNLOCKED := Color(0.682353, 0.819608, 0.309804, 0.95)  # AED14F
const LINE_LOCKED := Color(0.682353, 0.819608, 0.309804, 0.30)    # AED14F 低透明 = 明暗区分
const NODE_MAXED := Color(1.0, 1.0, 1.0)
const NODE_LOCKED := Color(0.4, 0.44, 0.4)
const NODE_READY := Color(0.72, 0.76, 0.70)      # 阶段已达标（绿 / 红圈）：介于满级亮色与锁暗之间
const RING_MAXED := Color(0.25, 0.62, 1.0, 0.95)   # 满级 / 已解锁（无法再升级）的蓝色光圈
const RING_UPGRADEABLE := Color(0.45, 0.95, 0.42, 0.95)  # 满足升级条件、可立即升级的绿色光圈
const RING_NO_RES := Color(0.95, 0.32, 0.28, 0.95)       # 研究所阶段已达标但资源不足的红色光圈

# 底部小 tip：每次打开科技树随机抽一条
const TIP_PREFIX := "tip："
const TIPS: PackedStringArray = [
	"你可以帮机器人挖矿，机器人也可以帮你挖矿",
	"这个界面也可以拖动哦",
	"这个时代不止有人类，仿生人甚至是一些星球的主要人口",
	"地球曾经爆发过激烈的革命，还好它撑住了",
	"这些tips都是策划写的",
	"要骂就骂策划",
	"按住鼠标中键可以拖动地图",
	"R键可以隐藏/显示UI",
	"像你这样的工程师大多会失败，但你不会，因为这是增量游戏",
	"如果你成功了，会被人类联邦授勋为英雄，如果你失败了会被追封烈士，虽然两者都不会让你有更高的工资",
	"超人推动地球的时候在地球人看来是不是在倒立？",
]

const TEX_DESC_BG := ART + "UI_TechTree_DescBG.png"
const TEX_UPGRADE_BTN := ART + "UI_TechTree_UpgradeBtn.png"
const TEX_CLOSE := ART + "UI_TechTree_Close.png"

var _view_root: Control           # 缩放 / 平移容器
var _lines: Node2D                # 连线层（draw 信号绘制）
var _nodes: Dictionary = {}       # tech_id -> Control（TextureButton 或「?」占位 Panel）
var _node_badges: Dictionary = {} # tech_id -> 等级小字 Label
var _node_rings: Dictionary = {}  # tech_id -> 满级 / 已解锁蓝色光圈 Panel

# 介绍框（挂到每个节点下方，悬停时显隐，画面不再移动）
var _desc_root: Control
var _desc_title: Label
var _desc_cost: Label
var _desc_text: Label
var _desc_btn: TextureButton
var _desc_btn_glow: Panel          # 升级按钮的悬停高亮边框（纯描边，覆盖在按钮上）
var _desc_owner: Control = null   # 介绍框当前依附的节点

var _tip_label: Label             # 底部小 tip
var _tip_last: int = -1           # 上次抽到的 tip 下标（避免连续两次重复）

var _lab_panel: PanelContainer       # 「研究所升级」面板（高度随最终目标行显隐伸缩）
var _lab_cells: Array = []          # 6 个阶段格（阶段0~5），每格 {style, status, btn}
var _dome_row: Dictionary = {}      # 最终目标行（巨型氧气罩），结构同阶段格

var _zoom: float = 0.9
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_build_tree()
	_center_view()
	_refresh_all()
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	visible = false
	set_process(false)   # 关闭时不参与逐帧悬停检测


# 每帧轮询鼠标位置，决定介绍框的显示/隐藏。
# 不用 mouse_entered/mouse_exited：后者在鼠标移到按钮等子节点时语义复杂，会导致介绍框误消失。
func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse := get_global_mouse_position()
	# 1. 鼠标在介绍框内（含按钮）→ 保持当前介绍框
	if _desc_root.visible and _desc_root.get_global_rect().has_point(mouse):
		return
	# 2. 鼠标在某个已揭示节点上 → 显示该节点介绍框
	var tid := _hit_test_node(mouse)
	if tid != "":
		if _desc_owner != _nodes.get(tid):
			_show_desc(tid)
		return
	# 3. 鼠标不在节点也不在介绍框 → 隐藏
	if _desc_owner != null:
		_clear_desc()


# 命中测试：返回鼠标下已揭示节点的 tech_id（"" 表示没有）
func _hit_test_node(mouse: Vector2) -> String:
	for tid in _nodes:
		var node: Control = _nodes[tid]
		if not node.visible:
			continue
		# 节点在 ViewRoot 下，用全局矩形判断（含缩放/平移）
		if node.get_global_rect().has_point(mouse):
			return String(tid)
	return ""


# ==================== 开关 ====================
func _open() -> void:
	visible = true
	# 不暂停游戏（机器人 / 精炼炉照常运行），仅标记面板打开、屏蔽与游戏世界的交互
	GameManager.lab_open = true
	set_process(true)
	_refresh_tip()
	_refresh_all()


func _close() -> void:
	visible = false
	GameManager.lab_open = false
	set_process(false)
	_clear_desc()


# 场景销毁兜底：避免 lab_open 状态残留到下一个场景
func _exit_tree() -> void:
	GameManager.lab_open = false


# 供 HUD 左下角的 LAB 按钮调用（开/关切换）
func toggle() -> void:
	if visible:
		_close()
	else:
		_open()


func _on_inventory_changed(_inv: Dictionary) -> void:
	if visible:
		_refresh_all()


func _on_tech_unlocked(_tech_id: String) -> void:
	if visible:
		_refresh_all()


# ==================== UI 搭建 ====================
func _build_ui() -> void:
	# 背景压暗
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 全屏拦截：挡住背后的游戏世界，点击不会穿透到机器人 / 精炼炉 / 矿点
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_view_root = Control.new()
	_view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view_root)

	_build_desc_panel()
	_build_lab_panel()
	_build_close_button()
	_build_tip_label()


func _build_tree() -> void:
	# 连线层（画在节点之下）
	_lines = Node2D.new()
	_lines.draw.connect(_draw_lines)
	_view_root.add_child(_lines)

	# 节点
	for tid in POSITIONS:
		_build_node(tid)


func _build_node(tid: String) -> void:
	var pos: Vector2 = POSITIONS[tid]
	var icon_file: String = String(ICONS.get(tid, ""))
	var node: Control = null

	if icon_file != "" and ResourceLoader.exists(ICON_DIR + icon_file):
		var btn := TextureButton.new()
		btn.texture_normal = load(ICON_DIR + icon_file)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.size = Vector2(NODE_SIZE, NODE_SIZE)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_node_pressed.bind(tid))
		node = btn
	else:
		# 无图标的科技：圆形占位 + 问号
		var panel := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.2, 0.12, 0.9)
		style.set_corner_radius_all(int(NODE_SIZE * 0.5))
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.border_color = COLOR_ON_DARK
		panel.add_theme_stylebox_override("panel", style)
		panel.size = Vector2(NODE_SIZE, NODE_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 46)
		q.add_theme_color_override("font_color", COLOR_ON_DARK)
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(q)
		node = panel

	node.position = pos - Vector2(NODE_SIZE, NODE_SIZE) * 0.5
	node.pivot_offset = Vector2(NODE_SIZE, NODE_SIZE) * 0.5
	_view_root.add_child(node)
	_nodes[tid] = node

	# 满级 / 已解锁（无法再升级）时套在图标外的蓝色光圈
	var ring_inset := 5.0
	var ring_size := NODE_SIZE + ring_inset * 2.0
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = Vector2(-ring_inset, -ring_inset)
	ring.size = Vector2(ring_size, ring_size)
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0, 0, 0, 0)
	ring_style.draw_center = false
	ring_style.border_color = RING_MAXED
	ring_style.set_border_width_all(3)
	ring_style.set_corner_radius_all(int(ring_size * 0.5))
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.visible = false
	node.add_child(ring)
	_node_rings[tid] = ring

	# 节点下方等级小字
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", COLOR_ON_DARK)
	badge.size = Vector2(NODE_SIZE, 24)
	badge.position = pos + Vector2(-NODE_SIZE * 0.5, NODE_SIZE * 0.5 + 2.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_root.add_child(badge)
	_node_badges[tid] = badge


func _build_desc_panel() -> void:
	# 介绍框：紧贴节点右侧（节点空间 = ViewRoot 局部坐标），悬停时显隐，画面不移动
	_desc_root = Control.new()
	_desc_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 接收鼠标：移入介绍框时保持显示
	_desc_root.visible = false
	_desc_root.z_index = 30
	_desc_root.size = Vector2(DESC_W + 80.0, DESC_H)  # 底图 488 + 按钮右侧余量，给足命中区域
	_view_root.add_child(_desc_root)  # 必须挂在 ViewRoot 下：position 用的是 ViewRoot 局部坐标，且跟随缩放/平移

	# 介绍框底图（488×143 原始尺寸，不缩放）
	var bg := TextureRect.new()
	bg.texture = load(TEX_DESC_BG)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_root.add_child(bg)

	_desc_title = Label.new()
	_desc_title.position = Vector2(20, 10)
	_desc_title.size = Vector2(290, 32)
	_desc_title.add_theme_font_size_override("font_size", 22)
	_desc_title.add_theme_color_override("font_color", COLOR_ON_DESC)
	_desc_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_desc_title)

	_desc_cost = Label.new()
	_desc_cost.position = Vector2(310, 14)
	_desc_cost.size = Vector2(160, 26)
	_desc_cost.add_theme_font_size_override("font_size", 16)
	_desc_cost.add_theme_color_override("font_color", COLOR_ON_DESC)
	_desc_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_desc_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_desc_cost)

	_desc_text = Label.new()
	_desc_text.position = Vector2(20, 64)   # 靠下放在底图的半透明部分（避开上部亮绿标题区）
	_desc_text.size = Vector2(450, 72)
	_desc_text.add_theme_font_size_override("font_size", 13)
	_desc_text.add_theme_color_override("font_color", COLOR_ON_DARK)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_desc_text)

	# 购买按钮（双箭头），原始素材 65×129
	_desc_btn = TextureButton.new()
	_desc_btn.texture_normal = load(TEX_UPGRADE_BTN)
	_desc_btn.ignore_texture_size = true
	_desc_btn.stretch_mode = TextureButton.STRETCH_SCALE
	_desc_btn.size = Vector2(65, 129)
	_desc_btn.position = Vector2(492, 7)
	_desc_btn.pivot_offset = _desc_btn.size * 0.5
	_desc_btn.pressed.connect(_on_tech_upgrade_pressed)
	_desc_root.add_child(_desc_btn)

	# 悬停高亮边框：叠在按钮正上方的一层纯描边 Panel（不拦截鼠标）
	_desc_btn_glow = Panel.new()
	_desc_btn_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_btn_glow.position = _desc_btn.position
	_desc_btn_glow.size = _desc_btn.size
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.draw_center = false
	glow_style.border_color = Color(0.85, 1.0, 0.35, 1.0)
	glow_style.set_border_width_all(3)
	glow_style.set_corner_radius_all(4)
	_desc_btn_glow.add_theme_stylebox_override("panel", glow_style)
	_desc_btn_glow.visible = false
	_desc_root.add_child(_desc_btn_glow)
	_desc_btn.mouse_entered.connect(func() -> void: _desc_btn_glow.visible = true)
	_desc_btn.mouse_exited.connect(func() -> void: _desc_btn_glow.visible = false)


func _build_lab_panel() -> void:
	var panel := PanelContainer.new()
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.05, 0.06, 0.03, 0.92)
	base.content_margin_left = 12
	base.content_margin_right = 12
	base.content_margin_top = 10
	base.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", base)
	# 左侧竖排一列：x 24~236，y 24~480（标题 + 6 个阶段格）
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_right = 236
	panel.offset_bottom = 484
	_lab_panel = panel
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "研究所升级"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_ON_DARK)
	vbox.add_child(title)

	_lab_cells.clear()
	for stage in range(6):
		var cell := _build_lab_cell("阶段 %d" % stage)
		# 每一格都连同一个升级函数，内部按 GameManager.lab_stage 判断，只有下一阶段格会被启用
		cell["btn"].pressed.connect(_on_lab_upgrade_pressed)
		vbox.add_child(cell["root"])
		_lab_cells.append(cell)

	# 最终目标行：研究所阶段 5 达成后才浮现（见 _refresh_dome_row）
	_dome_row = _build_lab_cell("巨型氧气罩")
	_dome_row["btn"].pressed.connect(_on_dome_pressed)
	_dome_row["root"].visible = false
	vbox.add_child(_dome_row["root"])


# 面板里的一格：标题 + 状态/消耗 + 右侧按钮（阶段格与最终目标行共用，按钮回调由调用方连接）
func _build_lab_cell(title_text: String) -> Dictionary:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(188, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.06, 0.9)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	cell.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	cell.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = title_text
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", COLOR_ON_DARK)
	info.add_child(name_label)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color(0.75, 0.78, 0.7))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(status)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(52, 38)
	btn.add_theme_font_size_override("font_size", 13)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = true
	hbox.add_child(btn)

	return {"root": cell, "style": style, "status": status, "btn": btn}


func _build_close_button() -> void:
	var btn := TextureButton.new()
	btn.texture_normal = load(TEX_CLOSE)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.size = Vector2(56, 56)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -76
	btn.offset_right = -20
	btn.offset_top = 20
	btn.offset_bottom = 76
	btn.pivot_offset = btn.size * 0.5
	btn.pressed.connect(_close)
	btn.mouse_entered.connect(func() -> void: btn.scale = Vector2(1.1, 1.1))
	btn.mouse_exited.connect(func() -> void: btn.scale = Vector2.ONE)
	add_child(btn)


# 底部小 tip：贴底、左下角左对齐，纯文字不拦截鼠标（不挡地图拖动）
func _build_tip_label() -> void:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", COLOR_ON_DARK)   # 荧光绿
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = 24.0     # 左边距与「研究所升级」面板对齐
	lbl.offset_top = -56.0
	lbl.offset_bottom = -22.0
	_tip_label = lbl
	add_child(lbl)


# 随机抽一条 tip 显示（同一条不连续出现两次）
func _refresh_tip() -> void:
	if TIPS.is_empty():
		return
	var idx := randi() % TIPS.size()
	if TIPS.size() > 1 and idx == _tip_last:
		idx = (idx + 1) % TIPS.size()
	_tip_last = idx
	_tip_label.text = TIP_PREFIX + TIPS[idx]


# ==================== 连线 ====================
# 取节点的「直接父节点」：prereq 里第一个非 add_robot 的前置（add_robot 是几乎所有科技的
# 共同前置，属于根节点、不应被每个节点各自连线）。若 prereq 里只有 add_robot，则父就是 add_robot。
func _direct_parent(tid: String) -> String:
	var tech: Dictionary = GameManager.TECHS.get(tid, {})
	for pre in tech.get("prereq", []):
		var pid := String(pre)
		if pid == "add_robot":
			continue
		if POSITIONS.has(pid):
			return pid
	if POSITIONS.has("add_robot") and tid != "add_robot":
		return "add_robot"
	return ""


func _draw_lines() -> void:
	for tid in POSITIONS:
		if not _is_revealed(tid):
			continue  # 未揭示的节点不画它的边
		var pid := _direct_parent(tid)
		if pid == "":
			continue  # 根节点或父节点不存在
		if not _is_revealed(pid):
			continue  # 前置尚未揭示，不画
		# 已解锁的边用亮色，未解锁用暗色（不再用锁图标）
		var unlocked: bool = GameManager.get_tech_level(tid) >= 1
		var col := LINE_UNLOCKED if unlocked else LINE_LOCKED
		var end := _draw_orthogonal_line(POSITIONS[pid], POSITIONS[tid], col)
		_lines.draw_circle(end, 5.0, col)


# 连线在图标边缘外额外留出的间隙
const LINE_EDGE_GAP := 6.0
const LINE_WIDTH := 3.0

# 端头内缩量：图标外接半径 + 间隙，使连线止于图标边缘、不再贯穿图标
func _line_inset() -> float:
	return NODE_SIZE * 0.5 + LINE_EDGE_GAP


# 画纵横直角折线：父子共线（同 x 或同 y）画直线；否则「先横后竖」的 L 形折线。
# 先横后竖可让水平段落在父节点所在行（通常只有父一个节点）、垂直段落在子节点所在列，
# 避免折线横穿同一排的其它节点。
# 两端各内缩 _line_inset()，让线不进入图标内部；返回靠近子节点的端点（供锚点圆点定位）。
func _draw_orthogonal_line(from: Vector2, to: Vector2, col: Color) -> Vector2:
	var r := _line_inset()
	if is_equal_approx(from.x, to.x):
		var s := signf(to.y - from.y)
		var a := from + Vector2(0.0, s * r)
		var b := to - Vector2(0.0, s * r)
		_lines.draw_line(a, b, col, LINE_WIDTH)
		return b
	if is_equal_approx(from.y, to.y):
		var s := signf(to.x - from.x)
		var a := from + Vector2(s * r, 0.0)
		var b := to - Vector2(s * r, 0.0)
		_lines.draw_line(a, b, col, LINE_WIDTH)
		return b
	var corner := Vector2(to.x, from.y)
	var a := from + Vector2(signf(corner.x - from.x) * r, 0.0)
	var b := to - Vector2(0.0, signf(to.y - corner.y) * r)
	_lines.draw_line(a, corner, col, LINE_WIDTH)
	_lines.draw_line(corner, b, col, LINE_WIDTH)
	return b


# ==================== 状态刷新 ====================
func _refresh_all() -> void:
	for tid in _nodes:
		_refresh_node(tid)
	if _lines != null:
		_lines.queue_redraw()
	_refresh_lab_panel()
	if _desc_owner != null:
		_fill_desc(_desc_owner_tech())


func _desc_owner_tech() -> String:
	# 从 owner 节点反查科技 id（_nodes 反查）
	for tid in _nodes:
		if _nodes[tid] == _desc_owner:
			return String(tid)
	return ""


# 该科技是否「已揭示」：开局自带 → 恒显示；无前置 → 恒显示；有前置 → 所有前置都已解锁才显示。
# 形成「前置全部解锁后，才浮现其后置节点」的逐步揭示效果。
func _is_revealed(tid: String) -> bool:
	if GameManager.is_default_tech(tid):
		return true
	var tech: Dictionary = GameManager.TECHS.get(tid, {})
	var pre: Array = tech.get("prereq", [])
	if pre.is_empty():
		return true
	for p in pre:
		if GameManager.get_tech_level(String(p)) < 1:
			return false
	return true


# 单个节点的显隐 / 明暗 / 等级文字刷新
func _refresh_node(tid: String) -> void:
	if not _nodes.has(tid):
		return
	var node: Control = _nodes[tid]
	var badge: Label = _node_badges[tid]
	var revealed: bool = _is_revealed(tid)
	node.visible = revealed
	badge.visible = revealed
	if not revealed:
		return
	var lv: int = GameManager.get_tech_level(tid)
	var max_lv: int = GameManager.get_tech_max_level(tid)
	# 满级 / 一次性科技已解锁 → 蓝色；当前可升级 → 绿色；阶段达标但资源不足 → 红色（同一尺寸光圈）
	var ring: Panel = _node_rings.get(tid)
	if ring != null:
		var maxed: bool = lv >= max_lv
		var upgradeable: bool = not maxed and GameManager.can_unlock_tech(tid)
		var no_res: bool = not maxed and not upgradeable and _stage_ok(tid) and not _resources_ok(tid)
		ring.visible = maxed or upgradeable or no_res
		if ring.visible:
			var ring_style := ring.get_theme_stylebox("panel") as StyleBoxFlat
			if maxed:
				ring_style.border_color = RING_MAXED
			elif upgradeable:
				ring_style.border_color = RING_UPGRADEABLE
			else:
				ring_style.border_color = RING_NO_RES
	if lv >= max_lv:
		node.modulate = NODE_MAXED
	elif _stage_ok(tid):
		# 绿圈 / 红圈（阶段已达标）的升级项：图标取满级亮色与锁暗之间的中间亮度
		node.modulate = NODE_READY
	else:
		node.modulate = NODE_LOCKED
	if max_lv > 1:
		badge.text = "%d/%d" % [lv, max_lv]
	elif lv >= 1:
		badge.text = "已解锁"
	else:
		badge.text = ""


# 该科技下一级的研究所阶段要求是否已满足（与 GameManager.can_unlock_tech 判定一致）
func _stage_ok(tid: String) -> bool:
	var tech: Dictionary = GameManager.TECHS.get(tid, {})
	var n: int = GameManager.get_tech_level(tid)
	var arr: Array = tech.get("lab_stages", [])
	var need_stage: int = int(arr[clampi(n, 0, arr.size() - 1)]) if arr.size() > 0 else int(tech.get("lab_stage", 0))
	return need_stage <= GameManager.lab_stage


# 该科技下一级的资源是否足够
func _resources_ok(tid: String) -> bool:
	var cost := GameManager.get_tech_cost(tid)
	for item_type in cost:
		if GameManager.get_count(String(item_type)) < int(cost[item_type]):
			return false
	return true


func _refresh_lab_panel() -> void:
	var stage: int = GameManager.lab_stage
	var can: bool = GameManager.can_upgrade_lab()
	for i in range(_lab_cells.size()):
		var cell: Dictionary = _lab_cells[i]
		var style: StyleBoxFlat = cell["style"]
		var status: Label = cell["status"]
		var btn: Button = cell["btn"]
		var is_current: bool = i == stage
		# 当前阶段格加荧光绿边框高亮，其余无边框
		var bw: int = 2 if is_current else 0
		style.border_width_left = bw
		style.border_width_right = bw
		style.border_width_top = bw
		style.border_width_bottom = bw
		style.border_color = COLOR_ON_DARK

		if i < stage:
			status.text = "已达成"
			btn.text = "✓"
			btn.disabled = true
		elif i == stage:
			status.text = "当前阶段"
			btn.text = "●"
			btn.disabled = true
		elif i == stage + 1 and stage < 5:
			var cost: Dictionary = GameManager.LAB_STAGE_UPGRADE_COSTS[stage]
			var parts: PackedStringArray = []
			for item_type in cost:
				parts.append("%d %s" % [int(cost[item_type]), _item_name(String(item_type))])
			status.text = "消耗：" + "、".join(parts)
			btn.text = "升级"
			btn.disabled = not can
		else:
			status.text = "未开启"
			btn.text = "×"
			btn.disabled = true
	_refresh_dome_row(stage)


# 最终目标行「巨型氧气罩」：研究所阶段 5 达成后浮现，建成后显示 ✓
func _refresh_dome_row(stage: int) -> void:
	var root: Control = _dome_row.get("root")
	if root == null:
		return
	root.visible = stage >= 5
	# 面板高度随该行显隐伸缩（容器不计隐藏子节点的高度），避免内容溢出面板
	_lab_panel.offset_bottom = 484.0 + (76.0 if root.visible else 0.0)
	if not root.visible:
		return
	var status: Label = _dome_row["status"]
	var btn: Button = _dome_row["btn"]
	if GameManager.is_tech_unlocked("giant_dome"):
		status.text = "已建成"
		btn.text = "✓"
		btn.disabled = true
		return
	var cost: Dictionary = GameManager.get_tech_cost("giant_dome")
	var parts: PackedStringArray = []
	for item_type in cost:
		parts.append("%d %s" % [int(cost[item_type]), _item_name(String(item_type))])
	status.text = "消耗：" + "、".join(parts)
	btn.text = "建造"
	btn.disabled = not GameManager.can_unlock_tech("giant_dome")


func _item_name(item_type: String) -> String:
	return "铜锭" if item_type == "copper_ingot" else item_type


# ==================== 悬停与介绍框 ====================
func _clear_desc() -> void:
	if _desc_owner == null:
		return
	_desc_owner = null
	_desc_root.visible = false
	# 复位节点放大
	for tid in _nodes:
		_nodes[tid].scale = Vector2.ONE


func _show_desc(tid: String) -> void:
	_desc_owner = _nodes.get(tid)
	if _desc_owner == null:
		return
	_fill_desc(tid)
	# 介绍框贴在节点右侧（不移动画面）
	_position_desc(tid)
	_desc_root.visible = true
	# 悬停节点轻微放大
	for ntid in _nodes:
		_nodes[ntid].scale = Vector2(1.12, 1.12) if ntid == tid else Vector2.ONE


# 把介绍框放到悬停节点右侧（ViewRoot 局部坐标；跟随缩放/平移一起移动）
func _position_desc(tid: String) -> void:
	var node: Control = _nodes.get(tid)
	if node == null:
		return
	var center: Vector2 = POSITIONS[tid]
	# 介绍框紧贴节点右边缘：底图原始高 143，垂直居中
	_desc_root.position = center + Vector2(NODE_SIZE * 0.5 + 2.0, -DESC_H * 0.5)


func _fill_desc(tid: String) -> void:
	var tech: Dictionary = GameManager.TECHS.get(tid, {})
	if tech.is_empty():
		return
	_desc_title.text = String(tech.get("name", tid))
	var cost := GameManager.get_tech_cost(tid)
	var parts: PackedStringArray = []
	for item_type in cost:
		parts.append("%d" % int(cost[item_type]))
	_desc_cost.text = " / ".join(parts)
	_desc_text.text = _tech_status_text(tid)
	var can: bool = GameManager.can_unlock_tech(tid)
	_desc_btn.modulate = Color.WHITE if can else Color(0.45, 0.45, 0.45)
	# 切换到另一个科技时复位高亮，避免鼠标未移动却残留边框
	_desc_btn_glow.visible = false


# 描述 + 当前不可购买的原因（与 GameManager.can_unlock_tech 判定一致）
func _tech_status_text(tid: String) -> String:
	var tech: Dictionary = GameManager.TECHS.get(tid, {})
	var lines: PackedStringArray = []
	lines.append(String(tech.get("desc", "")))
	if GameManager.is_tech_unlocked(tid):
		lines.append("已研究完成")
		return "\n".join(lines)
	for pre in tech.get("prereq", []):
		if GameManager.get_tech_level(String(pre)) < 1:
			var pre_name: String = String(GameManager.TECHS.get(String(pre), {}).get("name", String(pre)))
			lines.append("🔒 需先研究：%s" % pre_name)
	var n: int = GameManager.get_tech_level(tid)
	var arr: Array = tech.get("lab_stages", [])
	var st: int = int(arr[clampi(n, 0, arr.size() - 1)]) if arr.size() > 0 else int(tech.get("lab_stage", 0))
	if st > GameManager.lab_stage:
		lines.append("▲ 需研究所阶段 %d" % st)
	if not GameManager.can_unlock_tech(tid) and lines.size() == 1:
		for item_type in GameManager.get_tech_cost(tid):
			if GameManager.get_count(String(item_type)) < int(GameManager.get_tech_cost(tid)[item_type]):
				lines.append("● 资源不足")
				break
	return "\n".join(lines)


# ==================== 点击 ====================
func _on_node_pressed(tid: String) -> void:
	# 点击节点：立即固定显示该科技介绍（等价悬停，方便触控 / 慢速查看）
	_show_desc(tid)


func _on_tech_upgrade_pressed() -> void:
	var tid := _desc_owner_tech()
	if tid == "":
		return
	if GameManager.unlock_tech(tid):
		_refresh_all()
	else:
		_refresh_all()


func _on_lab_upgrade_pressed() -> void:
	if not GameManager.upgrade_lab():
		return
	_refresh_all()
	# 阶段 5 达成：「巨型氧气罩」最终目标浮现 → 强制退出科技树，并在主界面上方播放终局提示
	if GameManager.lab_stage >= 5:
		_play_final_goal_intro()


# 关闭科技树 + 用主界面上方的剧情提示框（与开局教程同一个提示框）播放终局文案
func _play_final_goal_intro() -> void:
	var intro: Node = get_parent().find_child("IntroDialogue", true, false)
	if intro != null and intro.has_method("play_final_goal"):
		intro.call("play_final_goal")


# 建造巨型氧气罩（消耗 20000 铜锭，一次性）
func _on_dome_pressed() -> void:
	if GameManager.unlock_tech("giant_dome"):
		_refresh_all()


# ==================== 缩放 / 拖拽 ====================
func _center_view() -> void:
	# 计算节点包围盒，自适应缩放让整棵树初始可见并居中
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for tid in POSITIONS:
		var p: Vector2 = POSITIONS[tid]
		mn = mn.min(p)
		mx = mx.max(p)
	var center := (mn + mx) * 0.5
	var span := (mx - mn) + Vector2(NODE_SIZE, NODE_SIZE)  # 加上节点半径，含整颗节点
	var fit := minf(1800.0 / maxf(span.x, 1.0), 1000.0 / maxf(span.y, 1.0))
	_zoom = clampf(fit, ZOOM_MIN, 1.0)
	_pan = Vector2(960, 540) - center * _zoom
	_apply_view_transform()


func _apply_view_transform() -> void:
	_view_root.position = _pan
	_view_root.scale = Vector2(_zoom, _zoom)
	# 介绍框（技能详情 + 升级按钮）大小固定：反向抵消 ViewRoot 缩放，保持屏幕 1:1
	if _desc_root != null:
		_desc_root.scale = Vector2.ONE / maxf(_zoom, 0.001)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	# 以鼠标位置为锚点缩放：缩放前后鼠标下的内容点不变
	var content_pos: Vector2 = (screen_pos - _pan) / _zoom
	_zoom = new_zoom
	_pan = screen_pos - content_pos * _zoom
	_apply_view_transform()


func _input(event: InputEvent) -> void:
	# 开关键（TAB 打开/关闭、ESC 关闭）必须在 visible 判断之前处理，
	# 否则面板隐藏时直接 return，TAB 永远只能关闭、无法打开
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if visible:
				_close()
			else:
				_open()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_ESCAPE and visible:
			_close()
			get_viewport().set_input_as_handled()
			return
	if not visible:
		return
	# 与地图拖动同一种操作方式：中键拖动 + 滚轮缩放
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(get_global_mouse_position(), 1.1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(get_global_mouse_position(), 1.0 / 1.1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_drag_last = event.global_position
			else:
				_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.global_position - _drag_last
		if delta.length() > 4.0:
			_drag_moved = true
		_pan += delta
		_drag_last = event.global_position
		_apply_view_transform()
