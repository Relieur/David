extends Node

# ==================== 信号 ====================
signal inventory_changed(inventory: Dictionary)
signal tech_unlocked(tech_id: String)
signal robot_selected(robot: Node)              # 新增
signal ore_memory_shared(ore: Node)             # 机器人间共享记忆的矿点（信息交流能力）

# ==================== 数据 ====================
var inventory: Dictionary = {}
var tech_levels: Dictionary = {}                # 科技等级，替代 unlocked_techs
var selected_robot: Node = null                 # 当前选中的机器人

# ==================== 科技定义 ====================
# category: 分类（对应 CATEGORY_ORDER）
# max_level>1 表示可重复升级（如扩展矿区每级解锁一块）；默认 1 为一次性解锁
# prereq: 前置科技，需全部已解锁才能研究
const CATEGORY_ORDER := ["能力升级", "资源点升级", "机器人升级", "精炼炉升级", "巨型玻璃罩"]

const TECHS := {
	#能力升级
	"memory_auto": {"category": "能力升级", "name": "坐标点记忆、自动寻路", "desc": "机器人记忆矿点与仓库，空闲时自动前往", "cost": {"copper_ingot": 5}, "prereq": []},
	"fallow": {"category": "能力升级", "name": "休耕意识", "desc": "矿点耐久低于15%时跳过，恢复到80%以上才继续开采", "cost": {"copper_ingot": 20}, "prereq": ["memory_auto"]},
	"priority_sort": {"category": "能力升级", "name": "优先排序能力", "desc": "机器人优先前往最近的矿点或仓库", "cost": {"copper_ingot": 10}, "prereq": ["fallow"]},
	"density": {"category": "能力升级", "name": "密度感知能力", "desc": "机器人感知周围密度，避免拥堵（占位）", "cost": {"copper_ingot": 20}, "prereq": ["priority_sort"]},
	"info_share": {"category": "能力升级", "name": "信息交流能力", "desc": "机器人之间共享记忆的坐标点", "cost": {"copper_ingot": 15}, "prereq": ["priority_sort"]},
	"resource_swap": {"category": "能力升级", "name": "资源交换", "desc": "背包空余的机器人可接收同伴的矿物", "cost": {"copper_ingot": 25}, "prereq": ["priority_sort"]},
	"reproduce": {"category": "能力升级", "name": "繁殖能力", "desc": "满足条件时自动生成新机器人（上限80）", "cost": {"copper_ingot": 50}, "prereq": ["fallow", "density", "info_share", "resource_swap"]},
	#资源点升级
	"regen_speed": {"category": "资源点升级", "name": "资源再生速度", "desc": "提升矿点耐久恢复速度（每级 ×2.5）", "cost": {"copper_ingot": 100}, "prereq": [], "max_level": 2, "dynamic_cost": true},
	"ore_durability": {"category": "资源点升级", "name": "资源点耐久度", "desc": "提升矿点初始耐久（每级 ×1.5）", "cost": {"copper_ingot": 30}, "prereq": [], "max_level": 2, "dynamic_cost": true},
	"unlock_more_ores": {"category": "资源点升级", "name": "新的资源点", "desc": "解锁后 Reveal 下一个预放置的矿点区域", "cost": {"copper_ingot": 3}, "prereq": ["regen_speed"], "max_level": 40},
	#机器人升级
	"move_speed": {"category": "机器人升级", "name": "移动速度", "desc": "提升机器人移动速度", "cost": {"copper_ingot": 8}, "prereq": []},
	"robot_backpack": {"category": "机器人升级", "name": "机器人背包", "desc": "解锁背包扩容能力", "cost": {"copper_ingot": 8}, "prereq": []},
	"backpack_capacity": {"category": "机器人升级", "name": "背包容量", "desc": "提升机器人背包容量（每级 +1）", "cost": {"copper_ingot": 80}, "prereq": ["robot_backpack"], "max_level": 4, "dynamic_cost": true},
	"mine_speed": {"category": "机器人升级", "name": "采集速度", "desc": "缩短机器人采矿耗时（每级 -0.25 秒）", "cost": {"copper_ingot": 15}, "prereq": [], "max_level": 5, "dynamic_cost": true},
	"robot_count": {"category": "机器人升级", "name": "机器人数量上限", "desc": "提升可拥有的机器人数量上限（初始20，每级+20）", "prereq": [], "max_level": 3, "costs": [{"copper_ingot": 500}, {"copper_ingot": 800}, {"copper_ingot": 1200}]},
	"add_robot": {"category": "机器人升级", "name": "添加机器人", "desc": "每升一级立即获得一个机器人", "cost": {"copper_ingot": 5}, "prereq": [], "max_level": 80, "dynamic_cost": true, "cost_growth": 1.15},
	#精炼炉升级
	"smelt_speed": {"category": "精炼炉升级", "name": "煅烧速度", "desc": "提升精炼炉的烧制速度（每级 -0.25 秒）", "cost": {"copper_ingot": 50}, "prereq": [], "max_level": 5, "dynamic_cost": true, "lab_stage": 0},
	"double_smelt": {"category": "精炼炉升级", "name": "无中生有", "desc": "精炼炉有 15% 概率一次烧出两个铜锭", "cost": {"copper_ingot": 200}, "prereq": ["smelt_speed"], "lab_stage": 1},
	"smelt_crit": {"category": "精炼炉升级", "name": "暴击率", "desc": "提升精炼炉一次烧出两个铜锭的概率（每级 +15%）", "cost": {"copper_ingot": 200}, "prereq": ["double_smelt"], "max_level": 4, "dynamic_cost": true, "lab_stage": 2},
	#巨型玻璃罩
	"glass_dome": {"category": "巨型玻璃罩", "name": "建设玻璃罩", "desc": "建造巨型玻璃罩", "cost": {"copper_ingot": 100}, "prereq": []},
}

# ==================== 资源 ====================
func add_item(item_type: String, amount: int) -> void:
	if amount <= 0:
		return
	inventory[item_type] = inventory.get(item_type, 0) + amount
	inventory_changed.emit(inventory)

func remove_item(item_type: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if inventory.get(item_type, 0) < amount:
		return false
	inventory[item_type] -= amount
	if inventory[item_type] <= 0:
		inventory.erase(item_type)
	inventory_changed.emit(inventory)
	return true

func get_count(item_type: String) -> int:
	return inventory.get(item_type, 0)

# ==================== 科技等级 ====================
func get_tech_level(tech_id: String) -> int:
	return tech_levels.get(tech_id, 0)

func get_tech_max_level(tech_id: String) -> int:
	return TECHS.get(tech_id, {}).get("max_level", 1)

# 获取某科技下一次升级所需的消耗（支持动态消耗，如「添加机器人」「背包容量」随等级递增）
#   - costs 数组：固定阶梯消耗，按等级索引取值
#   - dynamic_cost：公式 C = C0 × r^n 逐项向上取整（C0 = cost 基础值，r = cost_growth 默认 1.5，n = 当前等级，第 1 次升级 n=0）
func get_tech_cost(tech_id: String) -> Dictionary:
	var tech: Dictionary = TECHS.get(tech_id, {})
	var n: int = get_tech_level(tech_id)
	# 固定阶梯消耗：costs 数组按等级索引取值（第 1 次升级用 costs[0]）
	var costs: Array = tech.get("costs", [])
	if costs.size() > 0:
		return costs[clampi(n, 0, costs.size() - 1)]
	if tech.get("dynamic_cost", false):
		var growth: float = tech.get("cost_growth", 1.5)
		var result := {}
		for item_type in tech.get("cost", {}):
			result[item_type] = int(ceil(float(tech["cost"][item_type]) * pow(growth, float(n))))
		return result
	return tech.get("cost", {})

# 是否已满级
func is_tech_unlocked(tech_id: String) -> bool:
	return get_tech_level(tech_id) >= get_tech_max_level(tech_id)

# 是否可以解锁（存在 + 没满级 + 前置满足 + 资源够）
func can_unlock_tech(tech_id: String) -> bool:
	if not TECHS.has(tech_id):
		return false
	if is_tech_unlocked(tech_id):
		return false
	var tech: Dictionary = TECHS[tech_id]
	# add_robot 购买前拦截：机器人数量已达上限时不可购买
	if tech_id == "add_robot":
		var robot_max := 20 + 20 * get_tech_level("robot_count")
		if get_tree().get_nodes_in_group("robots").size() >= robot_max:
			return false
	# 前置科技必须全部已解锁
	for pre in tech.get("prereq", []):
		if not is_tech_unlocked(pre):
			return false
	for item_type in get_tech_cost(tech_id):
		if get_count(item_type) < get_tech_cost(tech_id)[item_type]:
			return false
	return true

# 解锁一次（等级 +1）
func unlock_tech(tech_id: String) -> bool:
	if not can_unlock_tech(tech_id):
		return false
	var cost := get_tech_cost(tech_id)
	for item_type in cost:
		remove_item(item_type, cost[item_type])
	tech_levels[tech_id] = get_tech_level(tech_id) + 1
	tech_unlocked.emit(tech_id)
	return true

# ==================== 机器人选中 ====================
func select_robot(robot: Node) -> void:
	selected_robot = robot
	robot_selected.emit(robot)

func deselect_robot() -> void:
	selected_robot = null
	robot_selected.emit(null)

# ==================== 清空 ====================
func clear() -> void:
	inventory.clear()
	tech_levels.clear()
	selected_robot = null
	inventory_changed.emit(inventory)
