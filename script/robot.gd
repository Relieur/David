extends CharacterBody2D
class_name Robot

# ==================== 导出参数 ====================
@export var move_speed: float = 300.0        # 移动速度
@export var mine_range: float = 80.0         # 进入这个距离就开始挖
@export var mine_time: float = 0.5           # 每次挖矿耗时
@export var carry_capacity: int = 5          # 携带上限
@export var deposit_range: float = 60.0      # 进入仓库这个距离就算卸货

# ==================== 节点引用 ====================
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# ==================== 内部状态 ====================
enum State { IDLE, MOVING, MINING, RETURNING, DEPOSITING }
var _state: State = State.IDLE

var _target_ore: Node2D = null               # 当前要挖的矿
var _warehouse: Node2D = null                # 仓库引用

var _is_selected: bool = false
var _carry_count: int = 0
var _command_token: int = 0                  # 每次指派新目标 +1，用于打断旧采矿循环
var _original_modulate: Color = Color.WHITE


# ==================== 生命周期 ====================
func _ready() -> void:
	input_pickable = true
	add_to_group("robots")
	collision_mask = 0                    # 机器人与彼此不硬碰撞，靠软分离避免重叠/挤住
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	if anim:
		_original_modulate = anim.modulate
		_play_anim("idle")
	_warehouse = get_tree().get_first_node_in_group("warehouse")
	GameManager.robot_selected.connect(_on_robot_selected)


# ==================== 点击选中 ====================
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		GameManager.select_robot(self)


func _on_robot_selected(robot: Node) -> void:
	_is_selected = (robot == self)
	if anim == null:
		return
	if _is_selected:
		anim.modulate = Color(0.6, 1.0, 0.6, 1.0)      # 选中变绿
	else:
		anim.modulate = _original_modulate


# ==================== 外部命令：挖某个矿 ====================
func set_mine_target(ore: Node2D) -> void:
	if ore == null or not is_instance_valid(ore):
		return
	_command_token += 1
	_target_ore = ore
	_state = State.MOVING
	print("机器人 %s 收到挖矿任务：%s" % [name, ore.name])


# ==================== 每帧逻辑 ====================
func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			_tick_idle()
		State.MOVING:
			_tick_moving()
		State.MINING:
			# 挖矿中不动，动画在 _start_mining 里已经播了
			velocity = Vector2.ZERO
			move_and_slide()
		State.RETURNING:
			_tick_returning()
		State.DEPOSITING:
			velocity = Vector2.ZERO
			move_and_slide()


# ==================== 避让：让机器人彼此推开，避免互相挤住 ====================
const SEPARATION_RADIUS := 48.0           # 两机器人中心小于此距离时互相推开
const SEPARATION_STRENGTH := 160.0        # 推开力度


func _get_separation_velocity() -> Vector2:
	var sep := Vector2.ZERO
	var others: Array[Node] = get_tree().get_nodes_in_group("robots")
	for other in others:
		if other == self or not is_instance_valid(other):
			continue
		var other2d := other as Node2D
		if other2d == null:
			continue
		var diff: Vector2 = global_position - other2d.global_position
		var d := diff.length()
		if d > 0.001 and d < SEPARATION_RADIUS:
			sep += diff.normalized() * (SEPARATION_RADIUS - d) / SEPARATION_RADIUS * SEPARATION_STRENGTH
	return sep


# ==================== 待机 ====================
func _tick_idle() -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_play_anim("idle")


# ==================== 走向矿石 ====================
func _tick_moving() -> void:
	if _target_ore == null or not is_instance_valid(_target_ore):
		# 目标丢了
		_target_ore = null
		_go_idle_or_return()
		return

	var dist := global_position.distance_to(_target_ore.global_position)

	if dist <= mine_range:
		velocity = Vector2.ZERO
		move_and_slide()
		_start_mining()
		return

	var dir := (_target_ore.global_position - global_position).normalized()
	velocity = dir * move_speed + _get_separation_velocity()
	move_and_slide()

	if anim and abs(dir.x) > 0.01:
		anim.flip_h = dir.x < 0
	_play_anim("walk")


# ==================== 回仓库 ====================
func _tick_returning() -> void:
	if _warehouse == null or not is_instance_valid(_warehouse):
		_warehouse = get_tree().get_first_node_in_group("warehouse")
		if _warehouse == null:
			_go_idle_or_return()
			return

	var dist := global_position.distance_to(_warehouse.global_position)

	if dist <= deposit_range:
		velocity = Vector2.ZERO
		move_and_slide()
		_start_deposit()
		return

	var dir := (_warehouse.global_position - global_position).normalized()
	velocity = dir * move_speed + _get_separation_velocity()
	move_and_slide()

	if anim and abs(dir.x) > 0.01:
		anim.flip_h = dir.x < 0
	_play_anim("walk")


# ==================== 开始挖矿 ====================
func _start_mining() -> void:
	if _state == State.MINING:
		return
	var ore := _target_ore
	if ore == null or not is_instance_valid(ore) or not ore.has_method("try_claim"):
		_target_ore = null
		_state = State.IDLE
		return
	if not ore.try_claim(self):
		# 这个格正被别的机器人采，放弃本次目标
		_target_ore = null
		_state = State.IDLE
		return
	_state = State.MINING
	_play_anim("mine")
	var token := _command_token

	# 到达矿点后自动循环挖矿，直到背包装满
	while _carry_count < carry_capacity:
		if not is_instance_valid(ore):
			break
		await get_tree().create_timer(mine_time).timeout

		# 期间被重新指派新矿点，本次循环作废
		if token != _command_token:
			ore.release(self)
			return
		if not is_instance_valid(ore) or not ore.has_method("mine"):
			break
		if ore.mine():
			_carry_count += 1
			print("机器人 %s 采到矿，携带 %d / %d" % [name, _carry_count, carry_capacity])

	if is_instance_valid(ore):
		ore.release(self)
	_target_ore = null

	# 背包装满后自行回仓库；否则（矿点丢失）回到待机
	if _carry_count >= carry_capacity:
		_state = State.RETURNING
	else:
		_state = State.IDLE


# ==================== 卸货 ====================
func _start_deposit() -> void:
	if _state == State.DEPOSITING:
		return
	_state = State.DEPOSITING

	# 卸货
	GameManager.add_item("copper", _carry_count)
	print("机器人 %s 卸货 %d 个铜矿" % [name, _carry_count])
	_carry_count = 0

	# 稍等一下再回去
	await get_tree().create_timer(0.3).timeout
	_state = State.IDLE


# ==================== 工具：回到待机 / 回仓库 ====================
func _go_idle_or_return() -> void:
	if _carry_count > 0:
		_state = State.RETURNING
	else:
		_state = State.IDLE


# ==================== 播放动画（避免每帧重播） ====================
func _play_anim(anim_name: String) -> void:
	if anim == null:
		return
	if anim.animation != anim_name or not anim.is_playing():
		anim.play(anim_name)
