extends ColorRect

const RADIUS := 163.0
const TRAIL_LEN := 20
const TRAIL_LIFETIME := 0.8

@export_group("Animation")
@export var rotation_speed := 0.24
@export var latitude_speed := 0.18
@export var cursor_move_time := 4.5
@export var pause_min := 1.8
@export var pause_max := 3.2

var _mat: ShaderMaterial
var _time := 0.0
var _cursor := Vector2(-48.0, -32.0)
var _from := Vector2(-48.0, -32.0)
var _to := Vector2(58.0, 45.0)
var _moving := true
var _elapsed := 0.0
var _duration := 4.5
var _pause := 0.0
var _trail: Array[Vector3] = []
var _trail_timer := 0.0


func _ready() -> void:
	_mat = material as ShaderMaterial
	if _mat == null:
		push_error("GlobeHUD needs a ShaderMaterial using globe_hud.gdshader.")
		return

	_mat.set_shader_parameter("rotation_speed", rotation_speed)
	_mat.set_shader_parameter("latitude_speed", latitude_speed)
	_duration = cursor_move_time
	_push_uniforms()


func _process(delta: float) -> void:
	if _mat == null:
		return

	# Avoid a large first-frame jump after the window regains focus.
	delta = minf(delta, 0.05)
	_time += delta
	_update_cursor(delta)
	_update_trail(delta)

	_push_uniforms()


func _random_target() -> Vector2:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * RADIUS * 0.6
	return Vector2(cos(angle), sin(angle)) * radius


func _start_next_move() -> void:
	_from = _cursor
	var target := _random_target()
	for _attempt in 10:
		if target.distance_to(_cursor) > 60.0:
			break
		target = _random_target()
	_to = target
	_elapsed = 0.0
	_duration = cursor_move_time * randf_range(0.9, 1.25)
	_moving = true


func _update_cursor(delta: float) -> void:
	if not _moving:
		_pause -= delta
		if _pause <= 0.0:
			_start_next_move()
		return

	_elapsed += delta
	var t := clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	var eased := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	_cursor = _from.lerp(_to, eased)
	if t >= 1.0:
		_moving = false
		_pause = randf_range(pause_min, pause_max)


func _update_trail(delta: float) -> void:
	_trail_timer += delta
	if _trail_timer >= 0.04:
		_trail_timer = fmod(_trail_timer, 0.04)
		_trail.append(Vector3(_cursor.x, _cursor.y, _time))
	while not _trail.is_empty() and _time - _trail[0].z > TRAIL_LIFETIME:
		_trail.pop_front()


func _push_uniforms() -> void:
	_mat.set_shader_parameter("time_val", _time)
	_mat.set_shader_parameter("cursor_pos", _cursor)

	# PackedVector3Array always has exactly TRAIL_LEN slots. Missing slots
	# reuse the oldest available point with zero alpha.
	var trail_data := PackedVector3Array()
	trail_data.resize(TRAIL_LEN)
	for i in TRAIL_LEN:
		var index := _trail.size() - TRAIL_LEN + i
		if index >= 0:
			var point := _trail[index]
			var alpha := maxf(0.0, 1.0 - (_time - point.z) / TRAIL_LIFETIME)
			trail_data[i] = Vector3(point.x, point.y, alpha)
		elif not _trail.is_empty():
			trail_data[i] = Vector3(_trail[0].x, _trail[0].y, 0.0)
		else:
			trail_data[i] = Vector3(_cursor.x, _cursor.y, 0.0)
	_mat.set_shader_parameter("trail", trail_data)
