extends ColorRect

var scan_material: ShaderMaterial
var scan_tween: Tween


func _ready() -> void:
	# Each icon owns its material so simultaneous scans stay independent.
	material = material.duplicate()
	scan_material = material as ShaderMaterial
	if scan_material == null:
		push_error("OreScanOverlay needs a ShaderMaterial.")
		return

	scan_material.set_shader_parameter("auto_play", false)
	scan_material.set_shader_parameter("enabled", false)
	resized.connect(_sync_size)
	_sync_size()


func _sync_size() -> void:
	if scan_material != null:
		scan_material.set_shader_parameter("overlay_size", size)


func play_increase() -> void:
	if scan_material == null:
		return
	if scan_tween != null and scan_tween.is_valid():
		scan_tween.kill()

	scan_material.set_shader_parameter("enabled", true)
	scan_material.set_shader_parameter("progress", 0.0)

	scan_tween = create_tween()
	scan_tween.tween_method(
		_set_progress,
		0.0,
		1.0,
		0.85
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	scan_tween.tween_callback(_finish_scan)


func _set_progress(value: float) -> void:
	scan_material.set_shader_parameter("progress", value)


func _finish_scan() -> void:
	scan_material.set_shader_parameter("enabled", false)
