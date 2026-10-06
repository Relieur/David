extends Node


#信号
signal  inventory_changed(inventory:Dictionary)
#数据
var inventory:Dictionary={}
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
