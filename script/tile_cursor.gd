extends Line2D

@onready var tile_map_layer: TileMapLayer = $"../TileMapLayer"


#一个光标的尺寸，表示一个tile_set
@export var tilemap:TileMapLayer
@export var tile_size:Vector2i=Vector2i(64,64)

func _ready() -> void:
	width=2.0
	default_color=Color("0b8700")
	antialiased=true
	z_index=1000
	top_level=true
	_draw_rect()


func _process(delta: float) -> void:
	#鼠标光标
	var mouse_world:=get_global_mouse_position()
	#隐藏框
	if _find_dropped_item(mouse_world)!=null:
		visible=false
		return
	
	
	#格子
	visible=true
	
	var cell:= tile_map_layer.local_to_map(tile_map_layer.to_local(mouse_world))
	
	global_position=tile_map_layer.to_global(tile_map_layer.map_to_local(cell))
	


func _find_dropped_item(world_pos : Vector2)->DroppedItem:
	var spece:=get_world_2d().direct_space_state
	var params:=PhysicsPointQueryParameters2D.new()
	params.position=world_pos
	params.collide_with_areas=true
	params.collide_with_bodies=false
	
	var hits:=spece.intersect_point(params,32)
	for hit in hits:
		if hit.collider is DroppedItem:
			return hit.collider
	return null





func _draw_rect()->void:
	clear_points()
	var h:=Vector2(tile_size)*0.5
	add_point(Vector2(-h.x,-h.y))
	add_point(Vector2(h.x,-h.y))
	add_point(Vector2(h.x,h.y))
	add_point(Vector2(-h.x,h.y))
	add_point(Vector2(-h.x,-h.y))
