extends Node2D

@onready var tilemap=$TileMapLayer
@onready var ore_container: Node2D = $OreContainer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
@onready var ware_house: WareHouse = $WareHouse



#预加载矿石
const ORE_SCENE:PackedScene=preload("res://scene/ore.tscn")

const DROPPED_ITEM_SCENE: PackedScene=preload("res://scene/dropped_item.tscn")


const TILE_SIZE=16
const MAP_SIZE=Vector2i(128,128)


const LAND_CAP=-0.3 	
const ORE_CAP = 0.55
#中心留空
const  NO_ORE_RADIUS:=20.0

func _ready() -> void:
	generate_world()
	_place_warehouse()#仓库
	_setup_camera()
	
	

#仓库放到中间
func _place_warehouse()->void:
	var center_cell:=Vector2i(MAP_SIZE.x /2,MAP_SIZE.y / 2)
	var pos:= Vector2( center_cell + Vector2i(1,1))*TILE_SIZE
	ware_house.set_center_to(pos)


#创造地图
func generate_world():
	
	
	#地面
	var height_noise=FastNoiseLite.new()
	#种子
	height_noise.seed=randi()
	height_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	height_noise.frequency=0.0004
	height_noise.fractal_octaves=2



	#矿物
	var copper_noise=FastNoiseLite.new()
	copper_noise.seed=height_noise.seed+1000
	copper_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	copper_noise.frequency=0.02
	copper_noise.fractal_octaves=2
	
	var center :=Vector2(MAP_SIZE.x*0.5,MAP_SIZE.y*0.5)
	
	var water_cells:Array[Vector2i]=[]
	var ground_cells:Array[Vector2i]=[]
	var copper_cells:Array[Vector2i]=[]

	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			var pos=Vector2i(x,y)
			var height=height_noise.get_noise_2d(x,y)
			
			if height<LAND_CAP:
				water_cells.append(Vector2i(x,y))
			else :
				ground_cells.append(pos)
				if Vector2(x,y).distance_to(center)<NO_ORE_RADIUS:
					continue
				if copper_noise.get_noise_2d(x,y)>ORE_CAP:
					copper_cells.append(pos)

	tilemap.set_cells_terrain_connect(water_cells,0,0)
	tilemap.set_cells_terrain_connect(ground_cells,0,1)
	#tilemap.set_cells_terrain_connect(ore_cells,0,2)
	for cell in copper_cells:
		var copper : =ORE_SCENE.instantiate()
		copper.global_position=tilemap.map_to_local(cell)
		copper.ore_type="copper"
		copper.amount=1
		ore_container.add_child(copper)
		copper.mined.connect(_on_copper_mined.bind(copper))
	print("水%d / 地面%d / 矿%d"%[water_cells.size(),ground_cells.size(),copper_cells.size()])

#摄像机
func _setup_camera()->void:
	
	camera_2d.set_target(ware_house.global_position)
	camera_2d.zoom=Vector2(2.0,2.0)
	camera_2d.map_size_px=Vector2(MAP_SIZE)*TILE_SIZE
	camera_2d.viewport_size=get_viewport_rect().size
	camera_2d.make_current()
	pass


#回调采集
func _on_copper_mined(ore_type:String ,amount :int ,ore:Node2D)->void:
	var drop : =DROPPED_ITEM_SCENE.instantiate()
	
	
	var angle:=randf()*TAU
	var radius:=randf_range(20.0,40.0)
	var offset:= Vector2(cos(angle),sin(angle))*radius
	
	
	drop.global_position=ore.global_position+offset
	drop.item_type=ore_type
	drop.amount=amount
	drop_container.add_child(drop)
	
	
	
	print("获得%s x %d"%[ore_type,amount])
	#背包
		
