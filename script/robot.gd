extends CharacterBody2D
class_name Robot

enum State { IDLE, MOVING_TO_ORE, MINING, MOVING_TO_WAREHOUSE, DEPOSITING }

@export var move_speed: float = 200.0
@export var max_capacity: int = 3
@export var mine_interval: float = 1.0  #采矿交互间隔（秒）
@export var arrive_threshold: float = 20.0  #到达目标的距离阈值
@export var separation_radius: float = 52.0  #鸟群分离半径
@export var separation_weight: float = 2.0  #分离力度

var backpack: int = 0
var carry_type: String = "copper"
var state: int = State.IDLE

var target_pos: Vector2 = Vector2.ZERO
var target_ore: Ore = null
var _mine_timer: float = 0.0
var _is_selected: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

const FRAME_COUNT := 65
const FRONT_PATH := "res://art/robot/walk_front/bot_front_%02d.png"
const BACK_PATH := "res://art/robot/walk_back/bot_back_%02d.png"


func _ready() -> void:
	add_to_group("robot")
	#机器人在第2层，只与第1层碰撞，机器人之间互不碰撞
	collision_layer = 2
	collision_mask = 1
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_build_animations()
	animated_sprite.play("walk_front")
	animated_sprite.pause()


#构建动画帧
func _build_animations() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("walk_front")
	frames.set_animation_speed("walk_front", 24.0)
	frames.set_animation_loop("walk_front", true)
	for i in FRAME_COUNT:
		frames.add_frame("walk_front", load(FRONT_PATH % i))

	frames.add_animation("walk_back")
	frames.set_animation_speed("walk_back", 24.0)
	frames.set_animation_loop("walk_back", true)
	for i in FRAME_COUNT:
		frames.add_frame("walk_back", load(BACK_PATH % i))

	animated_sprite.sprite_frames = frames


#点击选中
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		GameManager.select_robot(self)


func on_selected() -> void:
	_is_selected = true
	modulate = Color(1.4, 1.4, 1.0)


func on_deselected() -> void:
	_is_selected = false
	modulate = Color.WHITE


#选中时接收全局点击指令
func _unhandled_input(event: InputEvent) -> void:
	if not _is_selected:
		return
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_command(get_global_mouse_position())


#处理玩家点击指令：只有矿点或仓库才行动
func _handle_command(click_pos: Vector2) -> void:
	#检查是否点到仓库
	var warehouse := get_tree().get_first_node_in_group("warehouse")
	if warehouse and warehouse.is_point_inside(click_pos):
		_command_to_warehouse(warehouse)
		return
	#检查是否点到矿点（找点击位置附近最近的矿）
	var ore := _find_ore_near(click_pos)
	if ore:
		_command_to_ore(ore)
		return


#找点击位置附近（1格内）的矿点
func _find_ore_near(pos: Vector2) -> Ore:
	var closest: Ore = null
	var closest_dist: float = 48.0  #约0.75格
	for node in get_tree().get_nodes_in_group("ore"):
		var ore := node as Ore
		if not ore:
			continue
		var dist := ore.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = ore
	return closest


#指令：去采矿
func _command_to_ore(ore: Ore) -> void:
	if backpack >= max_capacity:
		return  #背包满了不采矿
	target_ore = ore
	target_pos = ore.global_position
	state = State.MOVING_TO_ORE


#指令：去仓库入库
func _command_to_warehouse(warehouse: WareHouse) -> void:
	if backpack <= 0:
		return  #空背包不去仓库
	target_pos = warehouse.global_position
	state = State.MOVING_TO_WAREHOUSE


func _physics_process(delta: float) -> void:
	#鸟群分离：所有状态下都生效，防止堆叠
	var separation := _get_separation_dir()
	match state:
		State.IDLE:
			animated_sprite.pause()
			if separation != Vector2.ZERO:
				position += separation * 60.0 * delta
		State.MOVING_TO_ORE, State.MOVING_TO_WAREHOUSE:
			_move_toward_target(delta, separation)
		State.MINING:
			_do_mining(delta)
			if separation != Vector2.ZERO:
				position += separation * 40.0 * delta
		State.DEPOSITING:
			_do_deposit()
			if separation != Vector2.ZERO:
				position += separation * 40.0 * delta


#计算分离方向：远离附近的其他机器人
func _get_separation_dir() -> Vector2:
	var steer := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("robot"):
		var other := node as Robot
		if not other or other == self:
			continue
		var diff := global_position - other.global_position
		var dist := diff.length()
		if dist < separation_radius and dist > 0.01:
			#越近排斥力越大
			steer += diff.normalized() * (1.0 - dist / separation_radius)
	return steer.normalized() * separation_weight


#朝目标移动（叠加分离方向）
func _move_toward_target(delta: float, separation: Vector2) -> void:
	var dir := target_pos - global_position
	var dist := dir.length()
	if dist <= arrive_threshold:
		_on_arrived()
		return
	dir = dir.normalized()
	#叠加分离力
	var final_dir := (dir + separation).normalized()
	velocity = final_dir * move_speed
	move_and_slide()
	#根据移动方向切换动画
	if final_dir.y > 0:
		animated_sprite.play("walk_front")
	else:
		animated_sprite.play("walk_back")


#到达目标
func _on_arrived() -> void:
	velocity = Vector2.ZERO
	if state == State.MOVING_TO_ORE:
		state = State.MINING
		_mine_timer = 0.0
	elif state == State.MOVING_TO_WAREHOUSE:
		state = State.DEPOSITING


#采矿逻辑：每 mine_interval 秒交互一次
func _do_mining(delta: float) -> void:
	animated_sprite.pause()
	if not target_ore or not is_instance_valid(target_ore):
		state = State.IDLE
		return
	if backpack >= max_capacity:
		state = State.IDLE
		return
	_mine_timer += delta
	if _mine_timer >= mine_interval:
		_mine_timer = 0.0
		if target_ore.robot_interact():
			backpack += 1
			if backpack >= max_capacity:
				state = State.IDLE


#入库逻辑
func _do_deposit() -> void:
	animated_sprite.pause()
	var warehouse := get_tree().get_first_node_in_group("warehouse") as WareHouse
	if warehouse:
		warehouse.robot_deposit(self)
	state = State.IDLE
