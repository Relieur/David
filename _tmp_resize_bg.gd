extends SceneTree

func _init() -> void:
	var src_path := "C:/Users/yidijieshi/.trae-cn/attachments/cd746589-f00f-43ca-8278-c0359ae7459f_50ec8609-b835-4fc9-9414-f730371505b0_bg2.png"
	var dst_path := "F:/新建文件夹/initial-project/David/art/bg2.png"
	var src := Image.load_from_file(src_path)
	if src == null:
		push_error("load failed")
		quit(1)
		return
	var sw := src.get_width()
	var sh := src.get_height()
	var dw := 1920
	var dh := 1080

	# 保持比例：求出缩放后尺寸
	var scale := min(float(dw) / sw, float(dh) / sh)
	var fw := int(round(sw * scale))
	var fh := int(round(sh * scale))
	var pad_x := (dw - fw) / 2
	var pad_y := (dh - fh) / 2
	var bottom_pad := dh - fh - pad_y

	# 取上下各 1 像素边缘条，稍后拉伸填补，保持横向渐变无缝
	var top_strip := src.get_region(Rect2i(0, 0, sw, 1))
	var bottom_strip := src.get_region(Rect2i(0, sh - 1, sw, 1))

	# 主图缩放到目标尺寸
	src.resize(fw, fh, Image.INTERPOLATE_LANCZOS)

	var dst := Image.create(dw, dh, false, Image.FORMAT_RGBA8)
	if pad_y > 0:
		top_strip.resize(dw, pad_y, Image.INTERPOLATE_NEAREST)
		dst.blit_rect(top_strip, Rect2i(0, 0, dw, pad_y), Vector2i(0, 0))
	if bottom_pad > 0:
		bottom_strip.resize(dw, bottom_pad, Image.INTERPOLATE_NEAREST)
		dst.blit_rect(bottom_strip, Rect2i(0, 0, dw, bottom_pad), Vector2i(0, dh - bottom_pad))
	dst.blit_rect(src, Rect2i(0, 0, fw, fh), Vector2i(pad_x, pad_y))

	var err := dst.save_png(dst_path)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("[pad] saved %dx%d scale=%.4f pad_y=%d bottom_pad=%d -> %s" % [dst.get_width(), dst.get_height(), scale, pad_y, bottom_pad, dst_path])
	quit()