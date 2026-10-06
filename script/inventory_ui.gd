extends Control
@onready var items: VBoxContainer = $Panel/Margin/VBox/Items
const ITEM_NAMES:={
	"copper":"铜",
	"iron":"铁",
	"gold":"金",
	
}
#首次渲染
func _ready() -> void:
	GameManager.inventory_changed.connect(_on_inventroy_changed)
	_refresh(GameManager.inventory)
	
	

func _on_inventroy_changed(inventory :Dictionary)->void:
	_refresh(inventory)

func _refresh(inventory:Dictionary)->void:
	for child in items.get_children():
		child.queue_free()
	
	if inventory.is_empty():
		var label:=Label.new()
		label.text="nothing"
		label.modulate=Color(0.6,0.6,0.6,1.0)
		items.add_child(label)
		return
	for item_type in inventory.keys():
		var label:=Label.new()
		var display_name:String=ITEM_NAMES.get(item_type,item_type)
		label.text="%s x %d"%[display_name,inventory[item_type]]
		items.add_child(label)
