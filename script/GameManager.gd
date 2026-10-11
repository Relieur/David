extends Node


#信号
signal  inventory_changed(inventory:Dictionary)
signal  robot_selection_changed(robot: Node2D)
signal  tech_unlocked(tech_id: String)
#数据
var inventory:Dictionary={}
#当前选中的机器人
var selected_robot: Node2D = null

#已解锁的科技
var _unlocked_techs: Dictionary = {}

#科技树定义：name 名称、desc 描述、cost 消耗资源、prereq 前置科技
const TECHS: Dictionary = {
	#能力升级
	"memory_auto": {"name": "坐标点记忆、自动寻路", "desc": "机器人记忆矿点与仓库，空闲时自动前往", "cost": {"copper": 5}, "prereq": []},
	"priority_sort": {"name": "优先排序能力", "desc": "机器人优先前往最近的矿点或仓库", "cost": {"copper": 10}, "prereq": ["memory_auto"]},
	"fallow": {"name": "休耕意识", "desc": "矿点耐久低于15%时跳过，恢复到80%以上才继续开采", "cost": {"copper": 20}, "prereq": ["priority_sort"]},
	"density": {"name": "密度感知能力", "desc": "机器人感知周围密度，避免拥堵（占位）", "cost": {"copper": 20}, "prereq": ["priority_sort"]},
	"info_share": {"name": "信息交流能力", "desc": "机器人之间共享记忆的坐标点", "cost": {"copper": 15}, "prereq": ["priority_sort"]},
	"resource_swap": {"name": "资源交换", "desc": "背包空余的机器人可接收同伴的矿物", "cost": {"copper": 25}, "prereq": ["priority_sort"]},
	"reproduce": {"name": "繁殖能力", "desc": "满足条件时自动生成新机器人（上限80）", "cost": {"copper": 50}, "prereq": ["fallow", "density", "info_share", "resource_swap"]},
	#资源点升级
	"regen_speed": {"name": "资源再生速度", "desc": "提升矿点耐久恢复速度", "cost": {"copper": 5}, "prereq": []},
	"ore_durability": {"name": "资源点耐久度", "desc": "提升矿点初始耐久", "cost": {"copper": 10}, "prereq": []},
	"ore_drop_count": {"name": "资源点掉落矿物数", "desc": "每次采集掉落更多矿物", "cost": {"copper": 15}, "prereq": ["ore_durability"]},
	"unlock_more_ores": {"name": "新的资源点", "desc": "解锁下一片矿区", "cost": {"copper": 15}, "prereq": ["regen_speed"]},
	#机器人升级
	"move_speed": {"name": "移动速度", "desc": "提升机器人移动速度", "cost": {"copper": 8}, "prereq": []},
	"robot_backpack": {"name": "机器人背包", "desc": "解锁背包扩容能力", "cost": {"copper": 8}, "prereq": []},
	"backpack_capacity": {"name": "背包容量", "desc": "提升机器人背包容量", "cost": {"copper": 15}, "prereq": ["robot_backpack"]},
	"mine_speed": {"name": "采集速度", "desc": "缩短机器人采矿交互间隔", "cost": {"copper": 10}, "prereq": []},
	"robot_count": {"name": "机器人数量上限", "desc": "提升可拥有的机器人数量上限", "cost": {"copper": 12}, "prereq": []},
	#巨型玻璃罩
	"glass_dome": {"name": "建设玻璃罩", "desc": "建造巨型玻璃罩", "cost": {"copper": 100}, "prereq": []},
}

#选中机器人
func select_robot(robot: Node2D) -> void:
	if selected_robot and selected_robot.has_method("on_deselected"):
		selected_robot.on_deselected()
	selected_robot = robot
	if robot and robot.has_method("on_selected"):
		robot.on_selected()
	robot_selection_changed.emit(robot)

#取消选中
func deselect_robot() -> void:
	select_robot(null)
#添加资源
func add_item(item_type :String,amount:int )->void:
	if amount <=0:
		return
	inventory[item_type]=inventory.get(item_type,0)+amount
	inventory_changed.emit(inventory)
#消耗
func  remove_item(item_type:String,amount:int)->bool:
	if amount<=0:
		return false
	if inventory.get(item_type,0)<amount:
		return false
	inventory[item_type]-=amount
	if inventory[item_type]<=0:
		inventory.erase(item_type)
	inventory_changed.emit(inventory)
	return true
#数量查询
func get_count(item_type:String)->int:
	return inventory.get(item_type,0)
func clear()->void:
	inventory.clear()
	inventory_changed.emit(inventory)

#是否已解锁
func is_tech_unlocked(tech_id: String) -> bool:
	return _unlocked_techs.get(tech_id, false)

#是否可解锁：存在、未解锁、前置满足、资源足够
func can_unlock_tech(tech_id: String) -> bool:
	if not TECHS.has(tech_id):
		return false
	if is_tech_unlocked(tech_id):
		return false
	var tech: Dictionary = TECHS[tech_id]
	#前置科技
	for pre in tech.get("prereq", []):
		if not is_tech_unlocked(pre):
			return false
	#资源
	var cost: Dictionary = tech.get("cost", {})
	for item_type in cost:
		if get_count(item_type) < cost[item_type]:
			return false
	return true

#解锁科技：扣除资源并广播
func unlock_tech(tech_id: String) -> bool:
	if not can_unlock_tech(tech_id):
		return false
	var tech: Dictionary = TECHS[tech_id]
	var cost: Dictionary = tech.get("cost", {})
	for item_type in cost:
		remove_item(item_type, cost[item_type])
	_unlocked_techs[tech_id] = true
	tech_unlocked.emit(tech_id)
	return true
