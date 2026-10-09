extends Node2D
class_name OrePatch


# 掉落一个矿物（掉到地图上由玩家拖运），world_pos 为掉落发生的位置
signal mineral_dropped(world_pos: Vector2)


# ==================== 采集规则 ====================
const BASE_INTERACT_TIME := 3        # 耐久正常时：每 3 次交互掉落 1 个矿物
const LOW_DUR_INTERACT_TIME := 4     # 耐久 <= 15% 时：每 4 次交互掉落 1 个矿物
const LOW_DURABILITY_THRESHOLD := 15.0
const DURABILITY_PER_DROP := 5.0     # 每掉落 1 个矿物，耐久下降 5%

const GRID_SIZE := 64                # 每个矿石格子的尺寸


@export var durability: float = 100.0
@export var regen_per_second: float = 1.0   # 耐久每秒恢复的百分比


var _interact_count: int = 0         # 距离下次掉落的当前交互计数
var _ores: Array = []


func _ready() -> void:
	_collect_ores()
	durability = _get_max_durability()
	_update_visual()


# 收集子节点里的所有矿石
func _collect_ores() -> void:
	_ores.clear()
	for child in get_children():
		if child is Ore:
			_ores.append(child)


# 机器人开采一次（产出直接进机器人背包，不产生掉落物）
func mine_once() -> bool:
	return _register_interaction()


# 玩家点击开采一次（掉落矿物时发出信号，由外部生成掉落物）
func player_mine_at(world_pos: Vector2) -> bool:
	if _register_interaction():
		mineral_dropped.emit(world_pos)
		return true
	return false


# 当前交互次数上限（耐久降低后变慢）
func _interact_time() -> int:
	if durability <= _get_max_durability() * 0.15:
		return LOW_DUR_INTERACT_TIME
	return BASE_INTERACT_TIME


# 最大耐久：基础 100，每级「资源点耐久度」科技 +50
func _get_max_durability() -> float:
	var level := GameManager.get_tech_level("ore_durability")
	return 100.0 + 50.0 * float(level)


# 补满到当前最大耐久（科技解锁后提升上限时调用）
func refill_to_max() -> void:
	durability = _get_max_durability()
	_update_visual()


# 当前耐久比例（0~1），供外部决策（如机器人休耕判断）
func get_durability_ratio() -> float:
	var max_d := _get_max_durability()
	if max_d <= 0.0:
		return 0.0
	return durability / max_d


# 累计一次交互，满 interact_time 时掉 1 矿并降低耐久，返回是否掉落
func _register_interaction() -> bool:
	_interact_count += 1
	if _interact_count < _interact_time():
		return false
	_interact_count = 0
	durability = maxf(0.0, durability - DURABILITY_PER_DROP)
	_update_visual()
	return true


# 耐久越低矿点整体越暗
func _update_visual() -> void:
	for ore in _ores:
		if not is_instance_valid(ore):
			continue
		var sprite := ore.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			var t := durability / _get_max_durability()
			sprite.modulate = Color(0.5 + t * 0.5, 0.5 + t * 0.5, 0.5 + t * 0.5, 1.0)
	queue_redraw()


# 耐久缓慢恢复（基础 regen_per_second，受「资源再生速度」科技加成，最多回到最大耐久）
func _process(delta: float) -> void:
	var max_d := _get_max_durability()
	if durability < max_d:
		durability = minf(max_d, durability + _get_regen_rate() * delta)
		_update_visual()


# 实际恢复速度：每级「资源再生速度」科技 +100%
func _get_regen_rate() -> float:
	var level := GameManager.get_tech_level("regen_speed")
	return regen_per_second * (1.0 + float(level))


# 在矿点上方绘制耐久条
func _draw() -> void:
	if _ores.is_empty():
		return
	var half := Vector2(GRID_SIZE, GRID_SIZE) * 0.5
	var min_pos := Vector2.INF
	var max_pos := -Vector2.INF
	for ore in _ores:
		if not is_instance_valid(ore):
			continue
		min_pos = min_pos.min(ore.position - half)
		max_pos = max_pos.max(ore.position + half)

	var cx := (min_pos.x + max_pos.x) * 0.5
	var bar_width := max_pos.x - min_pos.x
	var bar_y := min_pos.y - 24.0
	var bar_height := 8.0

	draw_rect(Rect2(cx - bar_width * 0.5, bar_y, bar_width, bar_height), Color(0.15, 0.15, 0.15, 0.85))
	var ratio := durability / _get_max_durability()
	draw_rect(Rect2(cx - bar_width * 0.5, bar_y, bar_width * ratio, bar_height), _durability_color(ratio))


func _durability_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.2, 0.85, 0.3, 0.9)
	elif ratio > 0.25:
		return Color(0.95, 0.75, 0.2, 0.9)
	return Color(0.9, 0.25, 0.2, 0.9)