extends Node


#信号
signal  inventory_changed(inventory:Dictionary)
signal tech_unlocked(_tech_id:String)


#数据
var inventory:Dictionary={ }
var unlocked_techs:Dictionary={ }


#科技定义
const TECHS={
	"unlock_more_ores":{
		"name":"扩展矿区",
		"desc":"解锁其他矿脉",
		"cost": {"copper":3} ,
		"max_level":40,
	},
}




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

#科技

func is_tech_unlocked(tech_id:String)->bool:
	return unlocked_techs.get(tech_id,false)

func can_unlock_tech(tech_id:String)->bool:
	if is_tech_unlocked(tech_id):
		return false
	if not TECHS.has(tech_id):
		return false
	for item_type in TECHS[tech_id]["cost"]:
		if get_count(item_type) < TECHS[tech_id]["cost"][item_type]:
			return false
	
	return true
	

func unlock_tech(tech_id:String)->bool:
	if not can_unlock_tech(tech_id):
		return false
	for item_type in TECHS[tech_id]["cost"]:
		remove_item(item_type,TECHS[tech_id]["cost"][item_type])
	unlocked_techs[tech_id]=true
	tech_unlocked.emit(tech_id)
	return true


func clear()->void:
	inventory.clear()
	inventory_changed.emit(inventory)
