extends Control
## 剧情提示框：进入主场景后依次显示多句引导文案，也可由游戏事件触发后续引导。
## - 所有句子共用同一个提示框，逐句替换文本
## - 第一句开始时整体淡入，最后一句结束后整体淡出
## - 文案不自动切换，只有鼠标左键点击才切换到下一句
## - 播放期间屏蔽游戏世界交互（相机移动、挖矿、炉子点击等）

## 开局剧情（进入主场景后自动播放）
const INTRO_LINES: PackedStringArray = [
	"让我看看档案......",
	"哦，你来自地球！这可相当罕见",
	"不过那都不重要了",
	"现在你是负责建设异星的工程师",
	"这里什么都没有，意味着你得从零开始",
	"现在有一个精炼炉和一个矿点",
	"你需要亲自去挖那些矿（鼠标连续点击）",
	"并投进炉子里（点击掉落物）",
	"先收集五个矿吧",
]

## 烧出 5 个铜锭后播放的引导
const FIVE_INGOT_LINES: PackedStringArray = [
	"现在你可以创造你的第一个帮手（点击左下角LAB）",
	"剩下的就由你自己探索吧",
]

## 仅有一个精炼炉且炉温降到 0 时播放的引导
const HEAT_EMPTY_LINES: PackedStringArray = [
	"精炼炉温度降到0效率会下降，记得鼓风（点击精炼炉）",
]

const FIVE_INGOT_THRESHOLD := 5   # 铜锭达到该数量时触发第二次引导
const INTRO_DELAY := 1.0           # 开场剧情延迟出现时长（秒）
const FADE_TIME := 0.5            # 淡入 / 淡出时长（秒）

@onready var _label: Label = $BG/Label

var _lines: PackedStringArray = []  # 当前要播放的文案组
var _index: int = 0                 # 当前播放到的句子下标
var _playing: bool = false          # 是否正在播放（尚未淡出）
var _fade_tween: Tween
var _pending: Array = []            # 待播队列：当前提示框播放期间触发的提示框先排队，等当前结束再依次播放

# 状态：开场剧情是否已播放完；五锭引导是否已触发
var _intro_done: bool = false
var _five_ingot_triggered: bool = false
var _heat_empty_triggered: bool = false   # 炉温归零引导是否已触发（仅一次）


func _ready() -> void:
	# 默认不拦截任何输入（mouse_filter=IGNORE），只有真正播放时才 STOP。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.furnace_heat_empty.connect(_on_furnace_heat_empty)
	# 开场剧情延迟 INTRO_DELAY 秒后出现（等待主界面/相机就绪）
	await get_tree().create_timer(INTRO_DELAY).timeout
	if not is_inside_tree():
		return
	play(INTRO_LINES)


# ==================== 对外：播放一组文案 ====================
func play(lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	if _playing:
		# 已有文案在播：不抢占，加入待播队列，等当前提示框完全结束后再依次播放
		_pending.append(lines)
		return
	_start(lines)


func _start(lines: PackedStringArray) -> void:
	_lines = lines
	_index = 0
	_playing = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP   # 播放期间全屏拦截：接收点击跳句 + 屏蔽下层交互
	GameManager.intro_playing = true
	_label.text = _lines[0]
	modulate.a = 0.0
	_fade_in()


# ==================== 铜锭数量监听：达到 5 触发第二次引导 ====================
func _on_inventory_changed(_inventory: Dictionary) -> void:
	_check_five_ingot()


# 检查是否已烧出 5 个铜锭（仅触发一次，且在开场剧情结束后才生效）
func _check_five_ingot() -> void:
	if _five_ingot_triggered or not _intro_done:
		return
	if GameManager.get_count("copper_ingot") >= FIVE_INGOT_THRESHOLD:
		_five_ingot_triggered = true
		play(FIVE_INGOT_LINES)


# ==================== 炉温归零监听：仅一个精炼炉且温度降到 0 触发引导 ====================
func _on_furnace_heat_empty(_furnace: Node) -> void:
	if _heat_empty_triggered:
		return
	# 开场剧情结束后才生效（避免开局阶段被误触发打断）
	if not _intro_done:
		return
	# 仅有一个精炼炉（group "furnace" 只含启用中的炉子）时才提示
	if get_tree().get_nodes_in_group("furnace").size() != 1:
		return
	_heat_empty_triggered = true
	play(HEAT_EMPTY_LINES)


# ==================== 逐句推进（仅鼠标点击驱动，不自动切换） ====================
func _advance() -> void:
	_index += 1
	if _index < _lines.size():
		_label.text = _lines[_index]
	else:
		_finish()


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	_intro_done = true
	_fade_out()


# ==================== 鼠标点击跳到下一句 ====================
func _gui_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 左键：跳下一句并消费事件（同时屏蔽下层挖矿/炉子点击）
			_advance()
			accept_event()
		# 中键 / 滚轮：不 accept，让其穿透到相机 _unhandled_input（提示框出现时仍可拖动地图）
		# （其它按钮同样放行）


# ==================== 淡入淡出 ====================
func _fade_in() -> void:
	_clear_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fade_out() -> void:
	_clear_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_on_fade_out_finished)


func _on_fade_out_finished() -> void:
	_clear_tween()
	_release()
	# 有排队中的提示框：等当前消失后按序播放下一个
	if not _pending.is_empty():
		var next_lines: PackedStringArray = _pending.pop_front()
		_start(next_lines)
		return
	# 队列空：补一次五锭检查（覆盖「开场期间就烧够 5 个」的漏触发）
	_check_five_ingot()


# 释放：隐藏 + 停止拦截 + 解锁游戏交互（任何结束路径都走这里）
func _release() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameManager.intro_playing = false


func _clear_tween() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
