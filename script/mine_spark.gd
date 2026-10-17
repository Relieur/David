extends Node2D
class_name MineSpark

# 挖矿火花：蓝绿色小颗粒从命中点四散飞出，播完自动回收。
# 由 OrePatch 在每次交互时生成，掉矿时用 power 放大成更明显的一簇。

@onready var _particles: CPUParticles2D = $Particles


func _ready() -> void:
	top_level = true
	z_index = 5
	_particles.emitting = true
	# 粒子全部飞完后再回收（lifetime + 速度余量）
	await get_tree().create_timer(_particles.lifetime + 0.2).timeout
	queue_free()


# power：1.0 = 普通一击，更大的值用于矿物掉落时的加量爆发
func setup(power: float) -> void:
	_particles.amount = int(round(_particles.amount * power))
	_particles.initial_velocity_min *= power
	_particles.initial_velocity_max *= power
	_particles.scale_amount_max *= power
