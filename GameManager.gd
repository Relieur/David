extends Node

# ==================== 信号 ====================
signal inventory_changed(inventory: Dictionary)
signal tech_unlocked(tech_id: String)
signal robot_selected(robot: Node)              # 新增
signal ore_memory_shared(patch: Node)           # 机器人间共享记忆的矿区（信息交流能力）

# ==================== 数据 ====================
var inventory: Dictionary = {}
var tech_levels: Dictionary = {}                # 科技等级，替代 unlocked_techs
var selected_robot: Node = null                 # 当前选中的机器人
var lab_stage: int = 0                          # 研究所阶段（0~5）

const LAB_STAGE_UPGRADE_COSTS := [              # 研究所升级消耗（铜锭）
	{"copper_ingot": 100},   # 0→1
	{"copper_ingot": 400},   # 1→2
	{"copper_ingot": 800},   # 2→3
	{"copper_ingot": 1000},  # 3→4
	{"copper_ingot": 1500},  # 4→5
]

# ==================== 科技定义 ====================
# category: 分类（对应 CATEGORY_ORDER）
# max_level>1 表示可重复升级（如扩展矿区每级解锁一块）；默认 1 为一次性解锁
# prereq: 前置科技，需全部已解锁才能研究
const CATEGORY_ORDER := ["能力升级", "资源点升级", "机器人升级", "精炼炉升级", "巨型玻璃罩"]

const TECHS := {
	#能力升级
	"memory_auto": {"category": "能力升级", "name": "坐标点记忆、自动寻路", "desc": "机器人记忆矿点与仓库，空闲时自动前往", "cost": {"copper_ingot": 5}, "prereq": ["add_robot"], "lab_stage": 1},
	"fallow": {"category": "能力升级", "name": "休耕意识", "desc": "矿点耐久低于15%时跳过，恢复到80%以上才继续开采", "cost": {"copper_ingot": 20}, "prereq": ["memory_auto", "add_robot"], "lab_stage": 2},
	"priority_sort": {"category": "能力升级", "name": "优先排序能力", "desc": "机器人优先前往最近的矿点或仓库", "cost": {"copper_ingot": 10}, "prereq": ["fallow", "add_robot"], "lab_stage": 2},
	"density": {"category": "能力升级", "name": "密度感知能力", "desc": "机器人感知周围密度，避免拥堵（占位）", "cost": {"copper_ingot": 20}, "prereq": ["fallow", "add_robot"], "lab_stage": 2},
	"info_share": {"category": "能力升级", "name": "信息交流能力", "desc": "机器人之间共享记忆的坐标点", "cost": {"copper_ingot": 15}, "prereq": ["fallow", "add_robot"], "lab_stage": 4},
	"resource_swap": {"category": "能力升级", "name": "资源交换", "desc": "背包空余的机器人可接收同伴的矿物", "cost": {"copper_ingot": 25}, "prereq": ["fallow", "add_robot"], "lab_stage": 3},
	"reproduce": {"category": "能力升级", "name": "繁殖能力", "desc": "满足条件时自动生成新机器人（上限80）", "cost": {"copper_ingot": 50}, "prereq": ["fallow", "density", "info_share", "resource_swap", "add_robot"], "lab_stage": 5},
	#资源点升级
	"regen_speed": {"category": "资源点升级", "name": "资源再生速度", "desc": "提升矿点耐久恢复速度（每级 ×2.5）", "cost": {"copper_ingot": 100}, "prereq": ["add_robot"], "max_level": 2, "dynamic_cost": true, "lab_stage": 0},
	"ore_durability": {"category": "资源点升级", "name": "资源点耐久度", "desc": "提升矿点初始耐久（每级 ×1.5）", "cost": {"copper_ingot": 30}, "prereq": ["add_robot"], "max_level": 2, "dynamic_cost": true, "lab_stage": 1},
	"unlock_more_ores": {"category": "资源点升级", "name": "新的资源点", "desc": "每次升级 Reveal 3 个预放置的矿点区域", "cost": {"copper_ingot": 150}, "prereq": ["add_furnace", "add_robot"], "max_level": 3, "dynamic_cost": true, "lab_stages": [1, 2, 3]},
	#机器人升级
	"move_speed": {"category": "机器人升级", "name": "移动速度", "desc": "提升机器人移动速度（每级 +60/+100/+160）", "prereq": ["add_robot"], "max_level": 3, "costs": [{"copper_ingot": 10}, {"copper_ingot": 50}, {"copper_ingot": 200}], "lab_stages": [0, 1, 2]},
	"backpack_capacity": {"category": "机器人升级", "name": "背包容量", "desc": "提升机器人背包容量（每级 +1）", "cost": {"copper_ingot": 80}, "prereq": ["add_robot"], "max_level": 4, "dynamic_cost": true, "lab_stage": 1},
	"mine_speed": {"category": "机器人升级", "name": "采集速度", "desc": "缩短机器人采矿耗时（每级 -0.25 秒）", "cost": {"copper_ingot": 15}, "prereq": ["add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stages": [0, 0, 0, 2, 2]},
	"robot_count": {"category": "机器人升级", "name": "机器人数量上限", "desc": "提升可拥有的机器人数量上限（初始20，每级+20）", "prereq": ["add_robot"], "max_level": 3, "costs": [{"copper_ingot": 500}, {"copper_ingot": 800}, {"copper_ingot": 1200}], "lab_stages": [3, 4, 5]},
	"add_robot": {"category": "机器人升级", "name": "添加机器人", "desc": "每升一级立即获得一个机器人", "cost": {"copper_ingot": 5}, "prereq": [], "max_level": 80, "dynamic_cost": true, "cost_growth": 1.15, "lab_stage": 0},
	#精炼炉升级
	"smelt_speed": {"category": "精炼炉升级", "name": "煅烧速度", "desc": "提升精炼炉的烧制速度（每级 -0.25 秒）", "cost": {"copper_ingot": 50}, "prereq": ["add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stage": 0},
	"double_smelt": {"category": "精炼炉升级", "name": "无中生有", "desc": "精炼炉有 15% 概率一次烧出两个铜锭", "cost": {"copper_ingot": 200}, "prereq": ["smelt_speed", "add_robot"], "lab_stage": 1},
	"smelt_crit": {"category": "精炼炉升级", "name": "暴击率", "desc": "提升精炼炉一次烧出两个铜锭的概率（每级 +15%）", "cost": {"copper_ingot": 200}, "prereq": ["double_smelt", "add_robot"], "max_level": 4, "dynamic_cost": true, "lab_stage": 2},
	"add_furnace": {"category": "精炼炉升级", "name": "扩建精炼炉", "desc": "在地图上新增一个精炼炉，并行烧制", "cost": {"copper_ingot": 80}, "prereq": ["regen_speed", "add_robot"], "max_level": 3, "dynamic_cost": true, "lab_stage": 1},
	#巨型玻璃罩
	"glass_dome": {"category": "巨型玻璃罩", "name": "建设玻璃罩", "desc": "建造巨型玻璃罩", "cost": {"copper_ingot": 100}, "prereq": ["add_robot"]},
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
	# 前置科技必须至少解锁1级（无需满级）
	for pre in tech.get("prereq", []):
		if get_tech_level(pre) < 1:
			return false
	# 研究所阶段门槛：该科技下一级 lab_stage 必须 <= 当前研究所阶段
	# 支持 lab_stages 数组（每级不同阶段）或单一 lab_stage
	var n: int = get_tech_level(tech_id)
	var tech_lab_stage: int = 0
	var lab_stages_arr: Array = tech.get("lab_stages", [])
	if lab_stages_arr.size() > 0:
		tech_lab_stage = lab_stages_arr[clampi(n, 0, lab_stages_arr.size() - 1)]
	else:
		tech_lab_stage = tech.get("lab_stage", 0)
	if tech_lab_stage > lab_stage:
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

# ==================== 研究所升级 ====================
func can_upgrade_lab() -> bool:
	if lab_stage >= LAB_STAGE_UPGRADE_COSTS.size():
		return false
	var cost: Dictionary = LAB_STAGE_UPGRADE_COSTS[lab_stage]
	for item_type in cost:
		if get_count(item_type) < cost[item_type]:
			return false
	return true

func upgrade_lab() -> bool:
	if not can_upgrade_lab():
		return false
	var cost: Dictionary = LAB_STAGE_UPGRADE_COSTS[lab_stage]
	for item_type in cost:
		remove_item(item_type, cost[item_type])
	lab_stage += 1
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
