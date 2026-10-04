extends Node2D

# 诊断：为什么"不能移动"
const WORLD := "res://wolrd.tscn"

func _ready() -> void:
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame

	var p: RigidBody2D = world.get_node_or_null("Player")
	var cam: Camera2D = p.get_node_or_null("Camera2D")

	print("=== 1. 玩家与相机 ===")
	print("  type      = ", p.get_class())
	print("  起始位置  = ", p.global_position)
	print("  sprite    = ", (p.get_node("Sprite2D") as Sprite2D).texture.resource_path.get_file())
	print("  sprite缩放= ", (p.get_node("Sprite2D") as Sprite2D).scale, " -> 实际约 ", 128*0.1578, "px")
	print("  碰撞体    = ", (p.get_node("CollisionShape2D").shape as RectangleShape2D).size)
	print("  Camera2D  = ", cam, "  enabled=", cam.enabled, "  当前相机=", get_viewport().get_camera_2d())

	print("\n=== 2. 地图是否有物理碰撞（决定会不会掉出去）===")
	var tml: TileMapLayer = world.get_node("TileMapLayer")
	var q := PhysicsPointQueryParameters2D.new()
	q.position = Vector2(100, 100)
	q.collision_mask = 1
	var hits := p.get_world_2d().direct_space_state.intersect_point(q, 8)
	print("  TileMapLayer 格子 (6,6) 处碰撞体数量 = ", hits.size())
	print("  TileMapLayer collision_layer = ", tml.collision_layer)

	print("\n=== 3. 关键：屏幕上看得到什么 ===")
	# 相机是玩家的子节点 -> 玩家永远在屏幕中心
	# 所以「地图在滚动」才等于「玩家在移动」
	await _snap()
	var before_map := _map_signature()
	print("  不按时，画面左边缘的地图特征 = ", before_map)

	for i in range(60):
		await get_tree().physics_frame
	print("  静止 60 帧后 pos = ", p.global_position, "  vel = ", p.linear_velocity)
	await _snap()
	var idle_map := _map_signature()
	print("  静止时地图特征 = ", idle_map, "  -> 与初始相同? ", before_map == idle_map)

	# 按住 D
	Input.action_press("move_right")
	for i in range(60):
		await get_tree().physics_frame
	var moved: Vector2 = p.global_position
	Input.action_release("move_right")
	await _snap()
	var move_map := _map_signature()
	print("  按D 60帧后 pos = ", moved, "  vel = ", p.linear_velocity)
	print("  按D时地图特征 = ", move_map, "  -> 地图变了? ", idle_map != move_map)

	var a: Image = _shots[0]
	var b: Image = _shots[2]
	a.save_png("res://verify/d_idle.png")
	b.save_png("res://verify/d_move.png")
	print("  画面变化像素 = ", _diff(a, b))

	get_tree().quit()

var _shots: Array[Image] = []

func _snap() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_shots.append(get_viewport().get_texture().get_image().duplicate())

## 取画面中线一行的颜色签名，代表「地图内容」
func _map_signature() -> String:
	var img: Image = _shots[_shots.size() - 1]
	var y := img.get_height() / 2
	var parts := PackedStringArray()
	for x in range(0, img.get_width(), 160):
		parts.append(img.get_pixel(x, y).to_html(false))
	return ",".join(parts)

func _diff(a: Image, b: Image) -> int:
	var n := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n
