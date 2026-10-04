extends Node2D

# 探针：只验证运行时事实，不猜测
const WORLD := "res://wolrd.tscn"

func _ready() -> void:
	print("=== A. InputMap 实际注册情况 ===")
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		var evs := InputMap.action_get_events(a)
		var desc := []
		for e in evs:
			if e is InputEventKey:
				desc.append("keycode=%d physical=%d" % [e.keycode, e.physical_keycode])
		print("  ", a, " 存在=", InputMap.has_action(a), " 事件数=", evs.size(), " ", desc)

	var world: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame

	var p: RigidBody2D = world.get_node_or_null("Player")
	print("\n=== B. 玩家节点 ===")
	print("  节点存在=", p != null, "  class=", p.get_class())
	print("  脚本=", p.get_script())
	print("  global_position=", p.global_position)
	print("  freeze=", p.freeze, " freeze_mode=", p.freeze_mode)
	print("  gravity_scale=", p.gravity_scale)
	print("  linear_velocity 初值=", p.linear_velocity)
	print("  collision_layer=", p.collision_layer, " collision_mask=", p.collision_mask)
	var cs := p.get_node_or_null("CollisionShape2D")
	print("  CollisionShape2D=", cs, " shape=", (cs.shape if cs else null))
	if cs and cs.shape is RectangleShape2D:
		print("  形状尺寸=", (cs.shape as RectangleShape2D).size)
	print("  _physics_process 是否存在=", p.has_method("_physics_process"))

	print("\n=== C. TileMapLayer 碰撞配置 ===")
	var tml: TileMapLayer = world.get_node("TileMapLayer")
	print("  collision_enabled=", tml.collision_enabled)
	print("  已用格子数=", tml.get_used_cells().size())

	print("\n=== D. 静止 30 帧（不按任何键）===")
	for i in range(30):
		await get_tree().physics_frame
	print("  pos=", p.global_position, " vel=", p.linear_velocity)

	print("\n=== E. 模拟按住 D（move_right）40 帧 ===")
	Input.action_press("move_right")
	for i in range(40):
		await get_tree().physics_frame
	print("  按D中: pos=", p.global_position, " vel=", p.linear_velocity)
	Input.action_release("move_right")

	print("\n=== F. 模拟按住 W（move_up）40 帧 ===")
	Input.action_press("move_up")
	for i in range(40):
		await get_tree().physics_frame
	print("  按W中: pos=", p.global_position, " vel=", p.linear_velocity)
	Input.action_release("move_up")

	print("\n=== G. 相机跟随情况 ===")
	var cam: Camera2D = p.get_node_or_null("Camera2D")
	if cam:
		print("  Camera2D pos=", cam.global_position, " enabled=", cam.enabled)
		print("  玩家在屏幕上的位置=", get_viewport().get_canvas_transform() * p.global_position)

	get_tree().quit()
