extends Node2D
class_name FlyTrail

# 掉落物飞向精炼炉时的粒子拖尾：黄 → 蓝绿。
# 颗粒发射在世界坐标里（use_local_coordinates = false），所以本体移动后旧颗粒会留在原地形成尾巴；
# 拖尾节点与掉落物同级，不受掉落物飞行时缩放动画的影响。

@onready var _particles: CPUParticles2D = $Particles

var _finished := false


func _ready() -> void:
	top_level = true
	z_index = 90          # 低于飞行中的掉落物（100），高于地表物件
	# 颗粒留在世界坐标（local_coords = false），本体移动后旧颗粒留在原地形成尾巴
	_particles.local_coords = false
	_particles.emitting = false   # 等 start() 再喷


# 由掉落物每帧调用，让拖尾跟着本体走
func follow(world_pos: Vector2) -> void:
	global_position = world_pos


# dir 为掉落物的飞行方向，颗粒朝反方向喷出
func start(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_particles.direction = -dir
	_particles.emitting = true


# 到达炉子 / 掉落物消失：停止喷射，等剩余颗粒飞完自动回收
func finish() -> void:
	if _finished:
		return
	_finished = true
	_particles.emitting = false
	await get_tree().create_timer(_particles.lifetime + 0.2).timeout
	queue_free()
