shader_type canvas_item;

// --- CRT 屏幕 ---
uniform float curvature : hint_range(0.0, 0.3) = 0.08;
uniform float scanline_count : hint_range(50.0, 600.0) = 180.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform float chroma : hint_range(0.0, 0.01) = 0.002;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float flicker : hint_range(0.0, 0.1) = 0.03;

// --- 滚动网格 ---
uniform vec4 grid_color : source_color = vec4(0.3, 1.0, 0.6, 1.0);
uniform float grid_size = 24.0;
uniform float grid_line_width = 1.0;
uniform float grid_strength : hint_range(0.0, 1.0) = 0.15;
uniform float grid_speed = 20.0;

// --- 扫光 ---
uniform float sweep_progress = 1.2;                              // 光条中心的横向位置,1.2 = 在屏幕右侧之外
uniform float sweep_width : hint_range(0.01, 0.4) = 0.08;        // 光条半宽
uniform float sweep_strength : hint_range(0.0, 2.0) = 0.8;       // 光条亮度
uniform vec4 sweep_color : source_color = vec4(0.8, 1.0, 0.9, 1.0);

vec2 curve_uv(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	p *= 1.0 + dot(p, p) * curvature;
	return p * 0.5 + 0.5;
}

float line_dist(float coord) {
	return abs(fract(coord / grid_size + 0.5) - 0.5) * grid_size;
}

void fragment() {
	vec2 uv = curve_uv(UV);

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 base = texture(TEXTURE, uv);
		vec3 col;
		col.r = texture(TEXTURE, uv + vec2(chroma, 0.0)).r;
		col.g = base.g;
		col.b = texture(TEXTURE, uv - vec2(chroma, 0.0)).b;

		// 扫描线
		float s = sin(uv.y * scanline_count * 6.28318) * 0.5 + 0.5;
		col *= 1.0 - scanline_strength * s;

		// 向左滚动的网格
		vec2 px = uv / TEXTURE_PIXEL_SIZE;
		float dx = line_dist(px.x + TIME * grid_speed);
		float dy = line_dist(px.y);
		float lx = 1.0 - smoothstep(0.0, grid_line_width, dx);
		float ly = 1.0 - smoothstep(0.0, grid_line_width, dy);
		col += grid_color.rgb * max(lx, ly) * grid_strength;

		// 暗角
		vec2 v = UV * 2.0 - 1.0;
		col *= clamp(1.0 - dot(v, v) * vignette_strength, 0.0, 1.0);

		// 闪烁
		col *= 1.0 + flicker * sin(TIME * 60.0);

		// 扫光:用弯曲后的 uv.x,光条会跟着屏幕弧度一起弯
		float band = 1.0 - smoothstep(0.0, sweep_width, abs(uv.x - sweep_progress));
		float core = 1.0 - smoothstep(0.0, sweep_width * 0.35, abs(uv.x - sweep_progress));
		vec3 light = mix(sweep_color.rgb, vec3(1.0), core);   // 白芯 + 彩边
		col += light * band * sweep_strength * base.a;

		COLOR = vec4(col, base.a);
	}
}
