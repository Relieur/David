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
# max_level>1 表示可重复升级（如扩展矿区每级解锁一块）；默认 1 为一次性解锁
# prereq 为前置科技，需全部已解锁才能研究
const TECHS := {
	"unlock_more_ores": {
		"name": "放置矿点",
		"desc": "花费铜矿，手动在地图指定位置放置一个固定形状的矿点",
		"cost": {"copper": 3},
		"max_level": 40,
	}
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
