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


func _ready() -> void:
	add_to_group("ore")
	input_pickable = true
	sprite_2d.texture = ORE_TEXTURES[randi() % ORE_TEXTURES.size()]
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


# 点击矿石：若已选中机器人则派它去挖（不计入玩家交互），否则玩家自行开采一次
func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("set_mine_target"):
			robot.set_mine_target(self)
		else:
			player_mine()


# 玩家直接开采一次（不经过机器人），掉落矿物由矿点信号通知外部
func player_mine() -> void:
	var patch := get_patch()
	if patch != null and patch.has_method("player_mine_at"):
		patch.player_mine_at(global_position)


# 机器人开采一次，返回是否真正产出矿物；耐久与交互计数统一交给所属矿点
func mine() -> bool:
	var patch := get_patch()
	if patch != null and patch.has_method("mine_once"):
		return patch.mine_once()
	return false


# ==================== 占地：一个格同时只能一个机器人采 ====================
func try_claim(miner: Node) -> bool:
	if _miner != null and _miner != miner:
		return false
	_miner = miner
	return true


func release(miner: Node) -> void:
	if _miner == miner:
		_miner = null


func is_occupied() -> bool:
	return _miner != null


func get_patch() -> Node2D:
	if _patch == null:
		_patch = get_parent()
	return _patch