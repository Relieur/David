extends CharacterBody2D
class_name Robot

# ==================== 导出参数 ====================
@export var move_speed: float = 80.0        # 移动速度
@export var mine_range: float = 80.0         # 进入这个距离就开始挖
@export var mine_time: float = 2          # 每次挖矿耗时
@export var carry_capacity: int = 1          # 携带上限
@export var deposit_range: float = 110.0     # 进入仓库这个距离就算卸货（3×3 炉子半宽 96，留出余量防止走进炉体）

# ==================== 节点引用 ====================
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# ==================== 内部状态 ====================
enum State { IDLE, MOVING, MINING, RETURNING, DEPOSITING }
var _state: State = State.IDLE

var _target_ore: Node2D = null               # 当前要挖的矿
var _furnace: RefiningFurnace = null         # 精炼炉引用

var _is_selected: bool = false
var _carry_count: int = 0
var _command_token: int = 0                  # 每次指派新目标 +1，用于打断旧采矿循环
var _original_modulate: Color = Color.WHITE
var known_patches: Array = []                # 记忆的矿区（OrePatch 节点引用，而非单个矿点格子）
var _swap_cooldown_until: int = 0            # 资源交换冷却时间戳（毫秒），防止来回倒腾


# ==================== 生命周期 ====================
func _ready() -> void:
	input_pickable = true
	add_to_group("robots")
	collision_mask = 0                    # 机器人与彼此不硬碰撞，靠软分离避免重叠/挤住
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if anim:
		_original_modulate = anim.modulate
		_play_anim("idle")
	_furnace = _find_nearest_furnace()
	GameManager.robot_selected.connect(_on_robot_selected)
	GameManager.tech_unlocked.connect(_on_tech_unlocked)
	GameManager.ore_memory_shared.connect(_on_ore_memory_shared)
	_update_carry_capacity()
	_update_mine_time()
	_update_move_speed()


# 科技升级回调：背包容量/采集速度/移动速度变化时刷新对应属性
func _on_tech_unlocked(tech_id: String) -> void:
	if tech_id == "backpack_capacity":
		_update_carry_capacity()
	elif tech_id == "mine_speed":
		_update_mine_time()
	elif tech_id == "move_speed":
		_update_move_speed()


# 根据「背包容量」科技等级刷新携带上限：基础 1，每级 +1
func _update_carry_capacity() -> void:
	carry_capacity = 1 + GameManager.get_tech_level("backpack_capacity")


# 根据「采集速度」科技等级刷新每次挖矿耗时：基础 2，每级 -0.25
func _update_mine_time() -> void:
	var level: int = GameManager.get_tech_level("mine_speed")
	mine_time = 2.0 - 0.25 * float(level)


# 根据「移动速度」科技等级刷新移动速度：基础 80，每级增量 [60, 100, 160]
const MOVE_SPEED_INCREMENTS: PackedFloat64Array = [60.0, 100.0, 160.0]
func _update_move_speed() -> void:
	var level: int = GameManager.get_tech_level("move_speed")
	var speed: float = 80.0
	for i in range(level):
		speed += MOVE_SPEED_INCREMENTS[i]
	move_speed = speed


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


# ==================== 悬停信息 ====================
func _on_mouse_entered() -> void:
	var popup: Node = get_tree().get_first_node_in_group("robot_popup")
	if popup and popup.has_method("show_for"):
		popup.show_for(self)


func _on_mouse_exited() -> void:
	var popup: Node = get_tree().get_first_node_in_group("robot_popup")
	if popup and popup.has_method("hide_popup"):
		popup.hide_popup(self)


# 当前状态的文本描述
func get_state_text() -> String:
	match _state:
		State.MINING:
			return "挖矿中"
		State.MOVING:
			return "赶路（去矿点）"
		State.RETURNING:
			return "赶路（回仓库）"
		State.DEPOSITING:
			return "卸货中"
		_:
			return "等待指令"


# 背包使用情况
func get_backpack_text() -> String:
	return "%d / %d" % [_carry_count, carry_capacity]


# 记忆的矿区坐标（未解锁坐标点记忆时返回空字符串）
func get_memory_text() -> String:
	if not _has_auto_return():
		return ""
	_cleanup_known_patches()
	if known_patches.is_empty():
		return ""
	var result := ""
	for i in known_patches.size():
		var pos: Vector2 = _get_patch_pos(known_patches[i])
		if i > 0:
			result += "  "
		result += "(%d, %d)" % [roundi(pos.x), roundi(pos.y)]
	return result


# 取矿区代表点：优先用矿区中心，退化到节点自身坐标
func _get_patch_pos(patch: Node) -> Vector2:
	if patch.has_method("get_center"):
		return patch.get_center()
	var n2d := patch as Node2D
	return n2d.global_position if n2d != null else Vector2.ZERO


# ==================== 外部命令：挖某个矿 ====================
func set_mine_target(ore: Node2D) -> void:
	if ore == null or not is_instance_valid(ore):
		return
	var patch: Node = ore.get_patch() if ore.has_method("get_patch") else null
	_remember_patch(patch)
	_command_token += 1
	_target_ore = ore
	_state = State.MOVING
	print("机器人 %s 收到挖矿任务：%s" % [name, ore.name])


# ==================== 外部命令：手动返回仓库卸货 ====================
# target_furnace 为空时自动选择离自己最近的精炼炉
func command_return(target_furnace: RefiningFurnace = null) -> void:
	_command_token += 1
	_target_ore = null
	_enter_returning(target_furnace)
	print("机器人 %s 收到手动返回仓库指令" % name)


# 进入返回状态：选卸货炉子。
# 指定了炉子就用指定的；否则解锁「优先排序能力」后每次选最近的，未解锁则沿用上一次的炉子
func _enter_returning(target_furnace: RefiningFurnace = null) -> void:
	if target_furnace != null and is_instance_valid(target_furnace):
		_furnace = target_furnace
	elif _has_priority_sort() or _furnace == null or not is_instance_valid(_furnace):
		_furnace = _find_nearest_furnace()
	_state = State.RETURNING


# ==================== 每帧逻辑 ====================
func _physics_process(delta: float) -> void:
	# 机器人深度排序由父节点 robot_container 的 y_sort_enabled 自动处理（按 y 坐标，下方遮盖上方）
	# 挖矿中不参与交换，避免干扰采矿循环
	if _state != State.MINING:
		_try_resource_swap()
	match _state:
		State.IDLE:
			_tick_idle(delta)
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
const DENSITY_RADIUS := 150.0             # 密度感知半径：统计此范围内的其他机器人
const DENSITY_PENALTY := 120.0            # 每个附近机器人折算的等效距离代价
const SWAP_RANGE := 60.0                  # 资源交换：与此距离内的同伴转交矿物


# 每物理帧只查询一次 "robots" 分组供全脚本复用，避免避让/密度/交换各自反复分配数组
static var _robots_frame: int = -1
static var _robots_buffer: Array = []

func _get_robots() -> Array:
	var f := Engine.get_physics_frames()
	if f != _robots_frame:
		_robots_frame = f
		_robots_buffer = get_tree().get_nodes_in_group("robots")
	return _robots_buffer


func _get_separation_velocity() -> Vector2:
	var sep := Vector2.ZERO
	var others: Array = _get_robots()
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
const DECIDE_INTERVAL := 0.25           # 空闲自动决策间隔：避免每帧遍历所有矿区/机器人算评分
var _decide_timer: float = 0.0

func _tick_idle(delta: float) -> void:
	# 节流：每隔 DECIDE_INTERVAL 才重新寻路决策一次，减少无谓的每帧计算
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = DECIDE_INTERVAL
		_auto_decide()
	if _state != State.IDLE:
		return
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

	_update_walk_anim(dir)


# 找离自己最近的精炼炉（多炉时自动分配，避免全涌向同一个）
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


# ==================== 回仓库 ====================
func _tick_returning() -> void:
	if _furnace == null or not is_instance_valid(_furnace):
		_furnace = _find_nearest_furnace()
		if _furnace == null:
			_go_idle_or_return()
			return

	var dist := global_position.distance_to(_furnace.global_position)

	if dist <= deposit_range:
		velocity = Vector2.ZERO
		move_and_slide()
		_start_deposit()
		return

	var dir := (_furnace.global_position - global_position).normalized()
	velocity = dir * move_speed + _get_separation_velocity()
	move_and_slide()

	_update_walk_anim(dir)


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
		# 该格正被别的机器人采：改去同矿区内另一个空闲矿点，避免都挤在同一格
		var patch: Node = ore.get_patch() if ore.has_method("get_patch") else null
		var alt: Node2D = _find_free_ore_in(patch)
		if alt != null and alt.try_claim(self):
			ore = alt
			_target_ore = alt
			# 新矿点可能超出采矿范围，保持移动状态继续靠近
			if global_position.distance_to(alt.global_position) > mine_range:
				return
		else:
			_target_ore = null
			_state = State.IDLE
			return
	_state = State.MINING
	var token := _command_token

	# 挖矿开始动画：播完再进入循环挖掘
	await get_tree().create_timer(_play_anim_get_duration("mine_start")).timeout
	# 等待期间被重新指派任务，本次采矿作废
	if token != _command_token:
		if is_instance_valid(ore):
			ore.release(self)
		return
	_play_anim("mine_loop")

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
		# 休耕意识：挖矿中耐久跌破 15% 则主动放弃该矿点
		if _has_fallow() and _is_ore_depleted(ore):
			print("机器人 %s 检测到矿点耐久过低，放弃开采" % name)
			break
		if ore.mine():
			_carry_count += 1
			print("机器人 %s 采到矿，携带 %d / %d" % [name, _carry_count, carry_capacity])

	if is_instance_valid(ore):
		ore.release(self)
	_target_ore = null

	# 挖矿结束动画：播完再离开矿点
	var end_wait := _play_anim_get_duration("mine_end")
	if end_wait > 0.0:
		var end_token := _command_token
		await get_tree().create_timer(end_wait).timeout
		# 等待期间被重新指派任务，交给新任务流程处理
		if end_token != _command_token:
			return

	# 背包装满：解锁「坐标点记忆、自动寻路」后自动回仓库，否则原地待命
	if _carry_count >= carry_capacity and _has_auto_return():
		_enter_returning()
	else:
		_state = State.IDLE


# ==================== 卸货 ====================
func _start_deposit() -> void:
	if _state == State.DEPOSITING:
		return
	_state = State.DEPOSITING

	# 把矿物投入精炼炉，进入烧制队列（产出铜锭）
	if _furnace != null and is_instance_valid(_furnace):
		_furnace.deposit_ore(_carry_count)
		print("机器人 %s 投入 %d 个铜矿进精炼炉" % [name, _carry_count])
	_carry_count = 0

	# 稍等一下再回去
	await get_tree().create_timer(0.3).timeout
	_state = State.IDLE


# ==================== 工具：回到待机 / 回仓库 ====================
func _go_idle_or_return() -> void:
	if _carry_count > 0 and _has_auto_return():
		_enter_returning()
	else:
		_state = State.IDLE


# 是否解锁「坐标点记忆、自动寻路」科技
func _has_auto_return() -> bool:
	return GameManager.is_tech_unlocked("memory_auto")


# ==================== 矿区记忆 ====================
# 记住一个矿区；broadcast=true 时若解锁信息交流则广播给其他机器人（接收共享时传 false 避免循环）
func _remember_patch(patch: Node, broadcast := true) -> void:
	if patch == null or not is_instance_valid(patch):
		return
	for p in known_patches:
		if p == patch:
			return
	known_patches.append(patch)
	if broadcast and _has_info_share():
		GameManager.ore_memory_shared.emit(patch)


# 接收其他机器人共享的矿区记忆
func _on_ore_memory_shared(patch: Node) -> void:
	_remember_patch(patch, false)


# 继承一批矿区记忆（新机器人生成时由管理器调用，不再向外广播以免循环传播）
func inherit_patches(patches: Array) -> void:
	for patch in patches:
		_remember_patch(patch, false)


# 是否解锁「信息交流能力」科技
func _has_info_share() -> bool:
	return GameManager.is_tech_unlocked("info_share")


# 清理失效引用，保证列表里都是有效节点
func _cleanup_known_patches() -> void:
	var valid: Array = []
	for p in known_patches:
		if is_instance_valid(p):
			valid.append(p)
	known_patches = valid


# 选下一个目标矿点：先按评分从已记忆矿区里选最优矿区，再在该矿区内挑一个空闲矿点
func _find_next_ore() -> Node:
	_cleanup_known_patches()
	# 收集「有可用空闲矿点」的矿区（休耕意识下还要求耐久恢复到 80% 以上）
	var candidates: Array = []
	for p in known_patches:
		if _has_fallow() and not _is_patch_ready(p):
			continue
		var ore := _find_free_ore_in(p)
		if ore != null:
			candidates.append({"patch": p, "ore": ore})
	if candidates.is_empty():
		return null
	# 未解锁优先排序且未解锁密度感知时，选第一个可用矿区里的空闲矿点
	if not _has_priority_sort() and not _has_density():
		return candidates[0]["ore"]
	# 评分越低越优（按矿区评分，使机器人分散到不同矿区）
	var best: Dictionary = candidates[0]
	var best_score: float = _patch_score(best["patch"])
	for c in candidates:
		var s: float = _patch_score(c["patch"])
		if s < best_score:
			best_score = s
			best = c
	return best["ore"]


# 在矿区里挑一个没被其他机器人占据的矿点（选离自己最近的，天然分散，兼容单个 Ore 节点）
func _find_free_ore_in(patch: Node) -> Node2D:
	if patch == null or not is_instance_valid(patch):
		return null
	var ores: Array = []
	if patch.has_method("get_ores"):
		ores = patch.get_ores()
	elif patch is Ore:
		ores = [patch]
	var best: Node2D = null
	var best_dist := INF
	for ore in ores:
		if not is_instance_valid(ore):
			continue
		if ore.has_method("is_occupied") and not ore.is_occupied():
			var d: float = global_position.distance_squared_to((ore as Node2D).global_position)
			if d < best_dist:
				best_dist = d
				best = ore as Node2D
	return best


# 矿区评分：距离越近分越低；密度感知解锁后，附近机器人越多分越高（惩罚拥堵）
func _patch_score(patch: Node) -> float:
	var pos: Vector2 = _get_patch_pos(patch)
	var score: float = global_position.distance_to(pos)
	if _has_density():
		var nearby: int = _count_robots_near(pos, DENSITY_RADIUS)
		score += float(nearby) * DENSITY_PENALTY
	return score


# 统计某位置半径内的其他机器人数（密度感知）
func _count_robots_near(pos: Vector2, radius: float) -> int:
	var count := 0
	for r in _get_robots():
		if r == self or not is_instance_valid(r):
			continue
		var r2d := r as Node2D
		if r2d != null and r2d.global_position.distance_to(pos) <= radius:
			count += 1
	return count


# 是否解锁「密度感知能力」科技
func _has_density() -> bool:
	return GameManager.is_tech_unlocked("density")


# ==================== 资源交换：把矿物转交给附近空背包的同伴去回仓库 ====================
func _try_resource_swap() -> void:
	if not _has_resource_swap():
		return
	if _carry_count <= 0:
		return
	# 冷却期内不再交换，防止与同伴来回倒腾
	if Time.get_ticks_msec() < _swap_cooldown_until:
		return
	var other := _find_swap_partner()
	if other == null:
		return
	var space: int = other.carry_capacity - other._carry_count
	if space <= 0:
		return
	var give: int = min(_carry_count, space)
	_carry_count -= give
	other._carry_count += give
	# 双方进入冷却（2 秒），留出时间彼此分开
	var cd: int = Time.get_ticks_msec() + 2000
	_swap_cooldown_until = cd
	other._swap_cooldown_until = cd
	other.command_return()
	print("机器人 %s 向 %s 转交 %d 个矿物" % [name, other.name, give])
	# 自己货已转空且正在回仓库：回到待机继续挖矿，避免空跑
	if _carry_count == 0 and _state == State.RETURNING:
		_state = State.IDLE


# 寻找附近可接收矿物的同伴（背包未满、比自己货少、且不在冷却中，避免互相倒腾）
func _find_swap_partner() -> Robot:
	var best: Robot = null
	var best_dist: float = SWAP_RANGE
	var now: int = Time.get_ticks_msec()
	for r in _get_robots():
		if r == self or not is_instance_valid(r):
			continue
		var other := r as Robot
		if other == null:
			continue
		if other._swap_cooldown_until > now:
			continue
		if other._carry_count >= other.carry_capacity or other._carry_count >= _carry_count:
			continue
		var d := global_position.distance_to(other.global_position)
		if d <= best_dist:
			best_dist = d
			best = other
	return best


# 是否解锁「资源交换」科技
func _has_resource_swap() -> bool:
	return GameManager.is_tech_unlocked("resource_swap")


# 矿区耐久是否 >= 80%（休耕意识下才会选为目标）；传入 Ore 时自动取其所属矿区
func _is_patch_ready(node: Node) -> bool:
	var patch: Node = node
	if node.has_method("get_patch"):
		patch = node.get_patch()
	if patch == null or not patch.has_method("get_durability_ratio"):
		return true
	return patch.get_durability_ratio() >= 0.8


# 矿点耐久是否 <= 15%（休耕意识下挖矿中跌破即放弃）
func _is_ore_depleted(ore: Node) -> bool:
	var patch: Node = ore.get_patch() if ore.has_method("get_patch") else null
	if patch == null or not patch.has_method("get_durability_ratio"):
		return false
	return patch.get_durability_ratio() <= 0.15


# 是否解锁「休耕意识」科技
func _has_fallow() -> bool:
	return GameManager.is_tech_unlocked("fallow")


# 是否解锁「优先排序能力」科技
func _has_priority_sort() -> bool:
	return GameManager.is_tech_unlocked("priority_sort")


# IDLE 时自动决策：解锁 memory_auto 后，背包满自动回仓，有空间自动去挖矿
func _auto_decide() -> void:
	if not _has_auto_return():
		return
	if _carry_count >= carry_capacity:
		_enter_returning()
		return
	if _carry_count < carry_capacity:
		var ore := _find_next_ore()
		if ore != null:
			_command_token += 1
			_target_ore = ore
			_state = State.MOVING


# ==================== 播放动画（避免每帧重播） ====================
func _play_anim(anim_name: String) -> void:
	if anim == null:
		return
	if anim.animation != anim_name or not anim.is_playing():
		anim.play(anim_name)


# 根据移动方向切换行走动画：向画面上方移动时播放背面行走动画
func _update_walk_anim(dir: Vector2) -> void:
	if anim == null:
		return
	if abs(dir.x) > 0.01:
		anim.flip_h = dir.x < 0
	if dir.y < 0.0:
		_play_anim("walk_back")
	else:
		_play_anim("walk")


# 播放动画并返回其时长（秒），供计时器等待一次性动画播完
func _play_anim_get_duration(anim_name: String) -> float:
	if anim == null or anim.sprite_frames == null:
		return 0.0
	var sf: SpriteFrames = anim.sprite_frames
	if not sf.has_animation(anim_name):
		return 0.0
	_play_anim(anim_name)
	var total := 0.0
	for i in sf.get_frame_count(anim_name):
		total += sf.get_frame_duration(anim_name, i)
	return total / maxf(sf.get_animation_speed(anim_name), 0.01)
