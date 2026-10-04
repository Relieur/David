extends Node2D

@onready var tilemap=$TileMapLayer

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
	var ore_noise=FastNoiseLite.new()
	ore_noise.seed=height_noise.seed+1000
	ore_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	ore_noise.frequency=0.008
	ore_noise.fractal_octaves=2

	var water_cells:Array[Vector2i]=[]
	var ground_cells:Array[Vector2i]=[]
	var ore_cells:Array[Vector2i]=[]

	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			var pos=Vector2i(x,y)
			var height=height_noise.get_noise_2d(x,y)




			if height<LAND_CAP:
				water_cells.append(Vector2i(x,y))
			else :
				ground_cells.append(pos)
				var ore_val=ore_noise.get_noise_2d(x,y)
				if ore_val>ORE_CAP:
					ore_cells.append(pos)

	tilemap.set_cells_terrain_connect(water_cells,0,0)
	tilemap.set_cells_terrain_connect(ground_cells,0,1)
	tilemap.set_cells_terrain_connect(ore_cells,0,2)
