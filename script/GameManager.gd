extends Node


#信号
signal  inventory_changed(inventory:Dictionary)
signal  robot_selection_changed(robot: Node2D)
#数据
var inventory:Dictionary={}
#当前选中的机器人
var selected_robot: Node2D = null

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
