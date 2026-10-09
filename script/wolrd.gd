extends Node2D

@onready var tilemap=$TileMapLayer
@onready var ore_container: Node2D = $OreContainer
@onready var camera_2d: CameraController = $Camera2D
@onready var drop_container: Node2D = $DropContainer
@onready var ware_house: WareHouse = $WareHouse
@onready var robot_container: Node2D = $RobotContainer



#预加载矿石
const ORE_SCENE:PackedScene=preload("res://scene/ore.tscn")

const DROPPED_ITEM_SCENE: PackedScene=preload("res://scene/dropped_item.tscn")

const ROBOT_SCENE: PackedScene = preload("res://scene/robot.tscn")


const TILE_SIZE=64

const MAP_SIZE=Vector2i(128,128)#画布尺寸
const LAND_CAP=-0.3 
const ORE_CAP = 0.55

const ORE_PATCH_COUNT:=40
const ORE_PATCH_MIN:=1
const ORE_PATCH_MAX:=6


#中心留空
const  NO_ORE_RADIUS:=10.0


func _ready() -> void:
	generate_world()
	_place_warehouse()#仓库
	_setup_camera()
	_spawn_robots()
	
	

#仓库放到中间
func _place_warehouse()->void:
	var center_cell:=MAP_SIZE /2
	var pos:= Vector2( center_cell)*TILE_SIZE+Vector2(TILE_SIZE,TILE_SIZE)*0.5
	ware_house.set_center_to(pos)


#在仓库附近生成初始机器人
func _spawn_robots() -> void:
	var count := 3
	for i in count:
		var robot: Robot = ROBOT_SCENE.instantiate()
		var angle := float(i) / float(count) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * TILE_SIZE * 1.5
		robot.global_position = ware_house.global_position + offset
		robot_container.add_child(robot)


#创造地图
func generate_world():
	
	
	#地面
	var height_noise=FastNoiseLite.new()
	#种子
	height_noise.seed=randi()
	height_noise.noise_type=FastNoiseLite.TYPE_SIMPLEX
	height_noise.frequency=0.0004
	height_noise.fractal_octaves=2
	
	
	
	
	var center :=Vector2(MAP_SIZE.x*0.5,MAP_SIZE.y*0.5)
	var water_cells:Array[Vector2i]=[]
	var center_cell:=Vector2i(MAP_SIZE.x /2,MAP_SIZE.y /2)
	var ground_cells:Array[Vector2i]=[]
	

	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			var pos=Vector2i(x,y)
			var height=height_noise.get_noise_2d(x,y)
			
			if height<LAND_CAP:
				water_cells.append(Vector2i(x,y))
			else :
				ground_cells.append(pos)
	
	var copper_cells:Array[Vector2i]=[]
	_generate_ore_patches(copper_cells,water_cells,center_cell)
	tilemap.set_cells_terrain_connect(water_cells,0,0)
	tilemap.set_cells_terrain_connect(ground_cells,0,1)
	
	for cell in copper_cells:
		var copper : =ORE_SCENE.instantiate()
		copper.global_position=tilemap.map_to_local(cell)
		copper.ore_type="copper"
		copper.amount=1
		ore_container.add_child(copper)
		copper.mined.connect(_on_copper_mined.bind(copper))
	print("地面%d / 矿%d"%[ground_cells.size(),copper_cells.size()])

#摄像机
func _setup_camera()->void:
	
	camera_2d.set_target(ware_house.global_position)
	camera_2d.zoom=Vector2(2.0,2.0)
	camera_2d.map_size_px=Vector2(MAP_SIZE)*TILE_SIZE
	camera_2d.viewport_size=get_viewport_rect().size
	camera_2d.make_current()



#生成矿物
func _generate_ore_patches(copper_cells:Array[Vector2i],water_cells:Array[Vector2i],center_cell:Vector2i)->void:
	var rng:=RandomNumberGenerator.new()
	rng.randomize()
	var water_set:={}
	for c in water_cells:
		water_set[c]=true
	var ore_set:={}
	var attemps:=0
	var max_attemps:=2000
	var target_ore_cells:=800
	while ore_set.size()<target_ore_cells and attemps<max_attemps:
		attemps+=1
		var cx=rng.randi_range(0,MAP_SIZE.x-1)
		var cy=rng.randi_range(0,MAP_SIZE.y-1)
		var origin:=Vector2i(cx,cy)
		if Vector2(origin).distance_to(Vector2(center_cell))<NO_ORE_RADIUS:
			continue
		var w:=rng.randi_range(ORE_PATCH_MIN,ORE_PATCH_MAX)
		var h:=rng.randi_range(ORE_PATCH_MIN,ORE_PATCH_MAX)
		if cx+w>MAP_SIZE.x or cy+h>MAP_SIZE.y:
			continue
		var ok:=true
		for dx in w:
			for dy in h:
				var c:=Vector2i(cx+dx,cy+dy)
				if water_set.has(c) or ore_set.has(c):
					ok=false
					break
			if not ok:
				break
		if  not ok:
			continue
		for dx in w:
			for dy in h:
				var c=Vector2i(cx+dx,cy+dy)
				ore_set[c]=true
	copper_cells.clear()
	for c in ore_set.keys():
		copper_cells.append(c)

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
		
