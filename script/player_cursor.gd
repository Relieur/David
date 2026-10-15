extends CanvasLayer
class_name PlayerCursor

# 玩家光标：用钻头贴图（drill.png，钻尖朝下）代替系统鼠标指针，
# 钻尖即热点（对准真实鼠标位置）；挖矿冷却期间在光标上方显示进度条。
# 鼠标悬停到 UI 控件上时自动隐藏钻头并恢复系统指针，保证按钮可正常点击。


const DRILL_TEXTURE := preload("res://art/robot/drill/drill.png")

# 光标改动总开关：false = 全部功能保留但不生效（沿用系统鼠标指针，不显示钻头与进度条）
@export var enabled: bool = false

@export var cursor_scale: float = 0.35   # 钻头贴图缩放（125x144 原图 → 约 44x50 像素）
@export var bar_width: float = 64.0      # 进度条宽度
@export var bar_height: float = 8.0      # 进度条高度
@export var bar_gap: float = 10.0        # 进度条与钻头顶端之间的间距

@onready var _drill: Sprite2D = $Drill
@onready var _bar: ProgressBar = $CooldownBar

var _sprite_height: float = 0.0          # 缩放后的钻头高度（像素）


func _ready() -> void:
	# 开关关闭：隐藏整个光标层、恢复系统鼠标，且不参与逐帧处理
	set_process(enabled)
	visible = enabled
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if enabled else Input.MOUSE_MODE_VISIBLE)
	if not enabled:
		return
	_drill.texture = DRILL_TEXTURE
	_drill.scale = Vector2.ONE * cursor_scale
	_sprite_height = DRILL_TEXTURE.get_size().y * cursor_scale
	_bar.size = Vector2(bar_width, bar_height)
	_bar.show_percentage = false


func _exit_tree() -> void:
	# 离开本场景（回开始界面等）时恢复系统指针
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	# 钻尖（贴图底部中点）对准鼠标位置
	_drill.position = mouse + Vector2(0.0, -_sprite_height * 0.5)
	# 进度条水平居中于光标，位于钻头顶部上方
	_bar.position = mouse + Vector2(-bar_width * 0.5, -_sprite_height - bar_gap - bar_height)
	# 冷却中显示进度（0 涨到 1），冷却结束自动隐藏
	var ratio := GameManager.get_player_mine_ratio()
	_bar.visible = ratio < 1.0
	_bar.value = ratio
	# 悬停 UI 控件时恢复系统指针并隐藏钻头，避免 UI 上没指针可点
	var over_ui := get_viewport().gui_get_hovered_control() != null
	visible = not over_ui
	if over_ui:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
