extends Area2D
class_name Ore


# 每个矿石格子随机选用这两张纹理之一
const ORE_TEXTURES: Array[Texture2D] = [
	preload("res://art/Ore/Resource_Ore01.png"),
	preload("res://art/Ore/Resource_Ore02.png"),
]


@onready var sprite_2d: Sprite2D = $Sprite2D


var _patch: Node2D = null
var _miner: Node = null              # 当前占据这个格子的机器人（一个格同时只能一个机器人采）
var _miner_token: int = 0            # 占用会话令牌：区分同一机器人的新旧采矿会话，避免旧协程误释放
var _mouse_held := false              # 玩家是否按住左键开采本矿石
var _mouse_over := false              # 指针是否悬停在本矿石上


func _ready() -> void:
	add_to_group("ore")
	input_pickable = true
	sprite_2d.texture = ORE_TEXTURES[randi() % ORE_TEXTURES.size()]
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


# 点击矿石：若已选中机器人则派它去挖（不计入玩家交互），否则玩家自行开采一次
func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 机器人优先级最高：点在机器人身上时让给机器人选中，跳过挖矿
		if Robot.is_point_over_robot(get_global_mouse_position()):
			return
		# 掉落物优先：若点击位置有掉落物覆盖（正在被玩家拖动），跳过挖矿
		if _is_point_over_dropped_item(get_global_mouse_position()):
			return
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("set_mine_target"):
			robot.set_mine_target(self)
			# 已经指定目的地，自动取消选中，避免下一次点矿仍派给同一机器人
			GameManager.deselect_robot()
		else:
			# 按住左键持续挖矿：_process 里会按冷却间隔反复调用 player_mine()
			_mouse_held = true
			player_mine()


func _on_mouse_entered() -> void:
	_mouse_over = true


func _on_mouse_exited() -> void:
	_mouse_over = false
	_mouse_held = false


# 按住左键持续挖矿：松开左键或指针移出矿石即停止
func _process(_delta: float) -> void:
	if not _mouse_held:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not _mouse_over:
		_mouse_held = false
		return
	player_mine()


# 判断某世界坐标是否被掉落物覆盖（掉落物优先级高于挖矿）
func _is_point_over_dropped_item(point: Vector2) -> bool:
	return DroppedItem.is_point_over_any_item(point)


# 玩家直接开采一次（不经过机器人），掉落矿物由矿点信号通知外部。
# 受全局「玩家挖掘间隔」限制：冷却中点击无效，光标上方进度条展示恢复进度。
func player_mine() -> void:
	if not GameManager.can_player_mine():
		return
	GameManager.start_player_mine_cooldown()
	var patch := get_patch()
	if patch != null and patch.has_method("player_mine_at"):
		patch.player_mine_at(global_position)


# 机器人开采一次，返回是否真正产出矿物；耐久与交互计数统一交给所属矿点
# 火花直接生成在机器人采的这个矿石格子上，而不是矿区中心
func mine() -> bool:
	var patch := get_patch()
	if patch != null and patch.has_method("mine_once"):
		return patch.mine_once(global_position)
	return false


# ==================== 占地：一个格同时只能一个机器人采 ====================
func try_claim(miner: Node, token: int = 0) -> bool:
	# 占格机器人已被释放：视为空闲，避免失效引用把矿格永久锁死
	if _miner != null and not is_instance_valid(_miner):
		_miner = null
		_miner_token = 0
	if _miner != null and _miner != miner:
		return false
	_miner = miner
	_miner_token = token
	return true


func release(miner: Node, token: int = -1) -> void:
	# token >= 0 时只释放对应会话，旧采矿协程不会误释放新会话的占用
	if _miner == miner and (token < 0 or token == _miner_token):
		_miner = null
		_miner_token = 0


func is_occupied() -> bool:
	return _miner != null and is_instance_valid(_miner)


func get_patch() -> Node2D:
	if _patch == null:
		_patch = get_parent()
	return _patch
