extends Node

# ==================== 信号 ====================
signal inventory_changed(inventory: Dictionary)
signal tech_unlocked(tech_id: String)
signal robot_selected(robot: Node)              # 新增

# ==================== 数据 ====================
var inventory: Dictionary = {}
var tech_levels: Dictionary = {}                # 科技等级，替代 unlocked_techs
var selected_robot: Node = null                 # 当前选中的机器人

# ==================== 科技定义 ====================
# category: 分类（对应 CATEGORY_ORDER）
# max_level>1 表示可重复升级（如扩展矿区每级解锁一块）；默认 1 为一次性解锁
# prereq: 前置科技，需全部已解锁才能研究
const CATEGORY_ORDER := ["能力升级", "资源点升级", "机器人升级", "巨型玻璃罩"]

const TECHS := {
	#能力升级
	"memory_auto": {"category": "能力升级", "name": "坐标点记忆、自动寻路", "desc": "机器人记忆矿点与仓库，空闲时自动前往", "cost": {"copper": 5}, "prereq": []},
	"priority_sort": {"category": "能力升级", "name": "优先排序能力", "desc": "机器人优先前往最近的矿点或仓库", "cost": {"copper": 10}, "prereq": ["memory_auto"]},
	"fallow": {"category": "能力升级", "name": "休耕意识", "desc": "矿点耐久低于15%时跳过，恢复到80%以上才继续开采", "cost": {"copper": 20}, "prereq": ["priority_sort"]},
	"density": {"category": "能力升级", "name": "密度感知能力", "desc": "机器人感知周围密度，避免拥堵（占位）", "cost": {"copper": 20}, "prereq": ["priority_sort"]},
	"info_share": {"category": "能力升级", "name": "信息交流能力", "desc": "机器人之间共享记忆的坐标点", "cost": {"copper": 15}, "prereq": ["priority_sort"]},
	"resource_swap": {"category": "能力升级", "name": "资源交换", "desc": "背包空余的机器人可接收同伴的矿物", "cost": {"copper": 25}, "prereq": ["priority_sort"]},
	"reproduce": {"category": "能力升级", "name": "繁殖能力", "desc": "满足条件时自动生成新机器人（上限80）", "cost": {"copper": 50}, "prereq": ["fallow", "density", "info_share", "resource_swap"]},
	#资源点升级
	"regen_speed": {"category": "资源点升级", "name": "资源再生速度", "desc": "提升矿点耐久恢复速度", "cost": {"copper": 5}, "prereq": []},
	"ore_durability": {"category": "资源点升级", "name": "资源点耐久度", "desc": "提升矿点初始耐久", "cost": {"copper": 10}, "prereq": []},
	"unlock_more_ores": {"category": "资源点升级", "name": "新的资源点", "desc": "解锁后 Reveal 下一个预放置的矿点区域", "cost": {"copper": 3}, "prereq": ["regen_speed"], "max_level": 40},
	#机器人升级
	"move_speed": {"category": "机器人升级", "name": "移动速度", "desc": "提升机器人移动速度", "cost": {"copper": 8}, "prereq": []},
	"robot_backpack": {"category": "机器人升级", "name": "机器人背包", "desc": "解锁背包扩容能力", "cost": {"copper": 8}, "prereq": []},
	"backpack_capacity": {"category": "机器人升级", "name": "背包容量", "desc": "提升机器人背包容量", "cost": {"copper": 15}, "prereq": ["robot_backpack"]},
	"mine_speed": {"category": "机器人升级", "name": "采集速度", "desc": "缩短机器人采矿交互间隔", "cost": {"copper": 10}, "prereq": []},
	"robot_count": {"category": "机器人升级", "name": "机器人数量上限", "desc": "提升可拥有的机器人数量上限", "cost": {"copper": 12}, "prereq": []},
	#巨型玻璃罩
	"glass_dome": {"category": "巨型玻璃罩", "name": "建设玻璃罩", "desc": "建造巨型玻璃罩", "cost": {"copper": 100}, "prereq": []},
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
	# 前置科技必须全部已解锁
	for pre in tech.get("prereq", []):
		if not is_tech_unlocked(pre):
			return false
	for item_type in tech.get("cost", {}):
		if get_count(item_type) < tech["cost"][item_type]:
			return false
	return true

# 解锁一次（等级 +1）
func unlock_tech(tech_id: String) -> bool:
	if not can_unlock_tech(tech_id):
		return false
	for item_type in TECHS[tech_id]["cost"]:
		remove_item(item_type, TECHS[tech_id]["cost"][item_type])
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
