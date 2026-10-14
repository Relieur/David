extends Control
@onready var items: VBoxContainer = $Panel/Margin/VBox/Items
const ITEM_NAMES:={
	"copper":"铜矿",
	"copper_ingot":"铜锭",

	
}
# 固定显示在最前面的两种物品（各占一行，纵向并列）：铜锭、炉内铜矿
const FIXED_ORDER := ["copper_ingot", "copper"]
# 显示名覆盖：「铜矿」这一行给的是所有精炼炉内的待烧总量，和仓库库存区分开
const NAME_OVERRIDES := {"copper": "炉内铜矿"}

# 已生成的 Label（item_type -> Label）与上次显示的数值，用于每帧轻量刷新
var _row_labels: Dictionary = {}
var _row_cache: Dictionary = {}


#首次渲染
func _ready() -> void:
	GameManager.inventory_changed.connect(_on_inventroy_changed)
	_refresh(GameManager.inventory)
	

func _on_inventroy_changed(inventory :Dictionary)->void:
	_refresh(inventory)

func _refresh(inventory:Dictionary)->void:
	for child in items.get_children():
		# 先摘掉再 queue_free，避免同一帧内新旧内容叠在一起
		items.remove_child(child)
		child.queue_free()
	_row_labels.clear()
	_row_cache.clear()

	# 排列顺序：先固定项（铜锭、炉内铜矿），再仓库里有的其它物品
	var order: Array = []
	for item_type in FIXED_ORDER:
		order.append(item_type)
	for item_type in inventory.keys():
		if order.has(item_type):
			continue
		order.append(item_type)

	# 每个物品一行，纵向排列
	for item_type in order:
		var amount := _get_amount(item_type)
		var label := Label.new()
		label.text = "%s x %d" % [_get_display_name(item_type), amount]
		items.add_child(label)
		_row_labels[item_type] = label
		_row_cache[item_type] = amount


# 某一行的数值：「铜矿」= 所有精炼炉内的待烧总量，其余 = 仓库库存
func _get_amount(item_type: String) -> int:
	if item_type == "copper":
		return GameManager.get_furnace_ore_total()
	return GameManager.get_count(item_type)


func _get_display_name(item_type: String) -> String:
	if NAME_OVERRIDES.has(item_type):
		return NAME_OVERRIDES[item_type]
	return ITEM_NAMES.get(item_type, item_type)


# 每帧刷新：炉内铜矿没有变化信号，只能轮询；数值没变就不重写 text
func _process(_delta: float) -> void:
	for item_type in _row_labels:
		var label: Label = _row_labels[item_type]
		if not is_instance_valid(label):
			continue
		var amount := _get_amount(item_type)
		if _row_cache.get(item_type, -1) == amount:
			continue
		_row_cache[item_type] = amount
		label.text = "%s x %d" % [_get_display_name(item_type), amount]
