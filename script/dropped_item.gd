extends Area2D
class_name DroppedItem

@export var item_type: String = "copper"
@export var amount: int = 1

@onready var sprite_2d: Sprite2D = $Sprite2D

const FLY_SPEED := 700.0    # 飞回仓库的速度（像素/秒）
const FLY_DURATION_MIN := 0.25  # 最短飞行时间（秒），避免近距离瞬移
const FLY_DURATION_MAX := 1.2   # 最长飞行时间（秒）

var _deposited: bool = false


func _ready() -> void:
	add_to_group("dropped_items")
	input_pickable = true
	z_index = 50
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


# 点击掉落物：自动飞回仓库并卸货
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 掉落物优先响应：吞掉本次输入，避免底下的矿点误触发挖矿
		get_viewport().set_input_as_handled()
		_fly_home()


# 找离自己最近的精炼炉
func _find_nearest_furnace() -> Node2D:
	var furnaces := get_tree().get_nodes_in_group("furnace")
	var best: Node2D = null
	var best_dist := INF
	for f in furnaces:
		if not is_instance_valid(f):
			continue
		var d := global_position.distance_to(f.global_position)
		if d < best_dist:
			best_dist = d
			best = f
	return best


# 飞向最近的精炼炉，到达后投入烧制
func _fly_home() -> void:
	if _deposited:
		return
	var furnace := _find_nearest_furnace()
	if furnace == null:
		return
	input_pickable = false
	z_index = 100
	var target: Vector2 = furnace.global_position
	var dist := global_position.distance_to(target)
	var duration := clampf(dist / FLY_SPEED, FLY_DURATION_MIN, FLY_DURATION_MAX)
	var tween := create_tween()
	# 位移：正弦缓动，起止速度都为 0，最平滑
	tween.tween_property(self, "global_position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 缩放：起飞放大 → 到达时缩到 0 消失，全程与位移并行同步结束
	tween.parallel().tween_property(self, "scale", Vector2(1.15, 1.15), duration * 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector2.ZERO, duration * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN) \
		.set_delay(duration * 0.3)
	tween.tween_callback(_deposit)


func _deposit() -> void:
	if _deposited:
		return
	_deposited = true
	var furnace := get_tree().get_first_node_in_group("furnace")
	if furnace != null and furnace.has_method("deposit_ore"):
		furnace.deposit_ore(amount)
	queue_free()
