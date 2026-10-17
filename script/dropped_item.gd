extends Area2D
class_name DroppedItem

@export var item_type: String = "copper"
@export var amount: int = 1

@onready var sprite_2d: Sprite2D = $Sprite2D

const FLY_SPEED := 700.0    # 飞回仓库的速度（像素/秒）
const FLY_DURATION_MIN := 0.25  # 最短飞行时间（秒），避免近距离瞬移
const FLY_DURATION_MAX := 1.2   # 最长飞行时间（秒）

# 飞行拖尾特效（黄 → 蓝绿），与掉落物同级，飞行时跟随、到达后自动回收
const FLY_TRAIL_SCENE: PackedScene = preload("res://scene/fly_trail.tscn")

var _deposited: bool = false
var _target_furnace: Node2D = null   # 本次飞行的目标炉子（到达后投给它，而不是重新找）
var _trail: Node2D = null            # 飞行时的拖尾节点


func _ready() -> void:
	add_to_group("dropped_items")
	input_pickable = true
	z_index = 50
	set_process(false)      # 只在飞行期间需要每帧驱动拖尾
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


# 飞行中：让拖尾跟着自己走
func _process(_delta: float) -> void:
	if _trail != null and is_instance_valid(_trail) and _trail.has_method("follow"):
		_trail.follow(global_position)


# 判断某世界坐标是否位于可点击的掉落物上（供矿点 / 精炼炉做点击优先级判断）
static func is_point_over_any_item(point: Vector2) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for item in tree.get_nodes_in_group("dropped_items"):
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


# 点击掉落物：自动飞回仓库并卸货
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 机器人优先级更高：点在机器人身上时让给机器人选中，本次不作回收
		if Robot.is_point_over_robot(get_global_mouse_position()):
			return
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
	_target_furnace = furnace
	input_pickable = false
	z_index = 100
	var target: Vector2 = furnace.global_position
	var dist := global_position.distance_to(target)
	var duration := clampf(dist / FLY_SPEED, FLY_DURATION_MIN, FLY_DURATION_MAX)
	# 起飞：生成拖尾，颗粒朝飞行反方向喷出
	_spawn_fly_trail((target - global_position).normalized())
	set_process(true)
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


# 生成飞行拖尾：挂在掉落物的父节点下（同级），避免被飞行缩放动画影响
func _spawn_fly_trail(dir: Vector2) -> void:
	var container := get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	_trail = FLY_TRAIL_SCENE.instantiate() as Node2D
	container.add_child(_trail)
	_trail.global_position = global_position
	if _trail.has_method("start"):
		_trail.start(dir)


# 结束拖尾（停止喷射，剩余颗粒飞完自动回收）
func _finish_fly_trail() -> void:
	if _trail != null and is_instance_valid(_trail):
		if _trail.has_method("finish"):
			_trail.finish()
		_trail = null


func _deposit() -> void:
	if _deposited:
		return
	var target := _target_furnace
	# 目标炉子飞行途中被停用 / 释放：改投最近的可用炉子，避免矿物凭空消失
	if target == null or not is_instance_valid(target) \
	or not target.has_method("deposit_ore") \
	or (target.has_method("is_active") and not target.is_active()):
		target = _find_nearest_furnace()
	if target == null:
		# 当前没有可用炉子：恢复成可点击状态，等玩家之后重新回收
		_target_furnace = null
		input_pickable = true
		z_index = 50
		scale = Vector2.ONE
		set_process(false)
		_finish_fly_trail()
		return
	_deposited = true
	target.deposit_ore(amount)
	_finish_fly_trail()
	queue_free()


# 兜底：掉落物因任何原因提前移除时，拖尾也要收尾
func _exit_tree() -> void:
	_finish_fly_trail()
