extends Node2D

@onready var tilemap=$TileMapLayer
@onready var ore_container: Node2D = $OreContainer

#预加载矿石
const ORE_SCENE:PackedScene=preload("res://scene/ore.tscn")


const MAP_SIZE=Vector2i(128,128)
const LAND_CAP=-0.3
const ORE_CAP = 0.2

func _ready() -> void:
	generate_world()


#创造地图
func generate_world():
	var noise =FastNoiseLite.new()

	#地面
	var height_noise=FastNoiseLite.new()
	#种子
	height_noise.seed=randi()
	height_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	height_noise.frequency=0.01
	height_noise.fractal_octaves=4



	#矿物
	var copper_noise=FastNoiseLite.new()
	copper_noise.seed=height_noise.seed+1000
	copper_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	copper_noise.frequency=0.008
	copper_noise.fractal_octaves=2

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
		copper.mined.connect(_on_copper_mined)
	print("水%d / 地面%d / 矿%d"%[water_cells.size(),ground_cells.size(),copper_cells.size()])
func _on_copper_mined(ore_type:String ,amount :int )->void:
	print("获得%s x %d"%[ore_type,amount])
	#背包
		
