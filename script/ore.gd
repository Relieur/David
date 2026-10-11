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
		# 掉落物优先：若点击位置有掉落物覆盖（正在被玩家拖动），跳过挖矿
		if _is_point_over_dropped_item(get_global_mouse_position()):
			return
		get_viewport().set_input_as_handled()
		var robot = GameManager.selected_robot
		if robot != null and is_instance_valid(robot) and robot.has_method("set_mine_target"):
			robot.set_mine_target(self)
		else:
			player_mine()


# 判断某世界坐标是否被掉落物覆盖（掉落物优先级高于挖矿）
func _is_point_over_dropped_item(point: Vector2) -> bool:
	var items := get_tree().get_nodes_in_group("dropped_items")
	for item in items:
		if not is_instance_valid(item):
			continue
		var dropped := item as DroppedItem
		if dropped == null or not dropped.input_pickable:
			continue
		var shape: Shape2D = null
		for child in dropped.get_children():
			if child is CollisionShape2D and child.shape != null:
				shape = child.shape
				break
		if shape == null:
			continue
		var local := dropped.to_local(point)
		if shape is RectangleShape2D:
			if Rect2(-shape.size * 0.5, shape.size).has_point(local):
				return true
		elif shape is CircleShape2D:
			if local.length() <= shape.radius:
				return true
	return false


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
