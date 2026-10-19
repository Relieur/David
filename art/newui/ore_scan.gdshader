shader_type canvas_item;
render_mode blend_add;

uniform vec4 scan_color : source_color = vec4(
	0.78, 1.0, 0.16, 1.0
);

uniform bool enabled = true;
uniform bool auto_play = false;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cycle_seconds : hint_range(0.2, 5.0) = 1.6;
uniform float moving_ratio : hint_range(0.1, 1.0) = 0.65;

uniform vec2 overlay_size = vec2(106.0, 106.0);
uniform vec2 circle_center = vec2(0.5, 0.5);
uniform float circle_radius : hint_range(0.1, 0.7) = 0.47;

uniform float band_width : hint_range(0.005, 0.15) = 0.035;
uniform float glow_width : hint_range(0.01, 0.3) = 0.10;
uniform float trail_length : hint_range(0.01, 0.4) = 0.16;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;


void fragment() {
	float short_side = max(min(overlay_size.x, overlay_size.y), 1.0);
	vec2 p = (UV - circle_center) * overlay_size / short_side;

	float distance_to_center = length(p);
	float edge_softness = max(fwidth(distance_to_center), 0.001);
	float circle_mask = 1.0 - smoothstep(
		circle_radius - edge_softness,
		circle_radius + edge_softness,
		distance_to_center
	);

	float scan_progress = progress;
	float playback_mask = 1.0;

	if (auto_play) {
		float phase = fract(TIME / max(cycle_seconds, 0.01));
		scan_progress = clamp(phase / moving_ratio, 0.0, 1.0);
		playback_mask = 1.0 - step(moving_ratio, phase);
	}

	float margin = max(trail_length, glow_width * 2.0) + band_width;
	float scan_y = mix(
		circle_radius + margin,
		-circle_radius - margin,
		scan_progress
	);
	float dy = p.y - scan_y;

	float band = 1.0 - smoothstep(
		band_width * 0.25,
		band_width,
		abs(dy)
	);
	float glow = exp(-pow(dy / max(glow_width, 0.001), 2.0) * 3.0);
	float trail = (
		1.0 - smoothstep(0.0, trail_length, dy)
	) * smoothstep(0.0, band_width, dy);

	float light = band * 0.85 + glow * 0.30 + trail * 0.20;
	float alpha = clamp(
		light * circle_mask * playback_mask * intensity,
		0.0,
		1.0
	);

	if (!enabled) {
		alpha = 0.0;
	}

	COLOR = vec4(scan_color.rgb, alpha * scan_color.a);
}
