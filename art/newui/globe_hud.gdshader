shader_type canvas_item;

const float DESIGN = 460.0;
const float TILT_X = 0.20;
const float TILT_Z = -0.08;
const float LON_COUNT = 20.0;
const float LAT_COUNT = 12.0;
const int TRAIL_LEN = 20;

uniform float time_val = 0.0;
uniform vec2 cursor_pos = vec2(-48.0, -32.0);
uniform vec3 trail[TRAIL_LEN];

uniform vec2 sphere_center = vec2(190.0, 230.0);
uniform float sphere_radius = 163.0;
uniform float rotation_speed = 0.24;
uniform float latitude_speed = 0.18;
uniform float line_width = 1.9;
uniform float major_width = 2.7;
uniform float back_opacity = 0.10;
uniform float fill_opacity = 0.0;
uniform vec3 tint : source_color = vec3(1.0);


float line_a(float dist, float width, float sc) {
	return clamp((width * 0.5 - dist) * sc + 0.5, 0.0, 1.0);
}


float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}


void over(inout vec3 col, inout float a, vec3 c, float ca) {
	float oa = ca + a * (1.0 - ca);
	col = (c * ca + col * a * (1.0 - ca)) / max(oa, 1e-5);
	a = oa;
}


// Spherical point -> view space (unit sphere, y up).
vec3 project(vec3 p, float rot) {
	float cy = cos(rot);
	float sy = sin(rot);
	float x1 = p.x * cy + p.z * sy;
	float y1 = p.y;
	float z1 = -p.x * sy + p.z * cy;

	float cx = cos(TILT_X);
	float sx = sin(TILT_X);
	float y2 = y1 * cx - z1 * sx;
	float z2 = y1 * sx + z1 * cx;

	float cz = cos(TILT_Z);
	float sz = sin(TILT_Z);
	return vec3(x1 * cz - y2 * sz, x1 * sz + y2 * cz, z2);
}


// View space -> (latitude, longitude) in radians. Inverse of project().
vec2 to_lat_lon(vec3 v, float rot) {
	float cz = cos(TILT_Z);
	float sz = sin(TILT_Z);
	float x1 = v.x * cz + v.y * sz;
	float y2 = -v.x * sz + v.y * cz;

	float cx = cos(TILT_X);
	float sx = sin(TILT_X);
	float y1 = y2 * cx + v.z * sx;
	float z1 = -y2 * sx + v.z * cx;

	float cy = cos(rot);
	float sy = sin(rot);
	float lx = x1 * cy - z1 * sy;
	float lz = x1 * sy + z1 * cy;
	return vec2(asin(clamp(y1, -1.0, 1.0)), atan(lx, lz));
}


// Analytic latitude / longitude grid coverage at the current fragment.
float grid_alpha(vec3 v, float rot, float lat_off, float sc, bool is_front) {
	vec2 ll = to_lat_lon(v, rot);

	float lon_step = TAU / LON_COUNT;
	float m = ll.y / lon_step;
	float idx = floor(m + 0.5);
	float dm = abs(m - idx) * lon_step;
	float gm = length(vec2(dFdx(dm), dFdy(dm))) + 1e-5;
	float major = mod(idx, 5.0) < 0.5 ? 1.0 : 0.0;
	float wm = max(mix(line_width, major_width, major) * sc, 1.0);
	float am = clamp(wm * 0.5 - dm / gm + 0.5, 0.0, 1.0);
	am *= is_front ? mix(0.58, 0.85, major) : back_opacity;

	// Latitude lines move north, wrap at the pole and fade near both poles.
	float u = (ll.x + PI * 0.5) / PI;
	float s = u - lat_off;
	float k = floor(s * LAT_COUNT + 0.5);
	float dl = abs(s * LAT_COUNT - k) / LAT_COUNT * PI;
	float gl = length(vec2(dFdx(dl), dFdy(dl))) + 1e-5;
	float u_line = fract(lat_off + k / LAT_COUNT);
	float fade = clamp(sin(u_line * PI) * 5.0, 0.0, 1.0);
	float wl = max(line_width * sc, 1.0);
	float al = clamp(wl * 0.5 - dl / gl + 0.5, 0.0, 1.0);
	al *= (is_front ? 0.58 : back_opacity) * fade;

	return max(am, al);
}


void fragment() {
	// One UV unit spans DESIGN design pixels. Derivatives keep strokes crisp
	// when the widget is scaled by the viewport or a Control container.
	float px_per_uv = 1.0 / max(length(vec2(dFdx(UV.x), dFdy(UV.x))), 1e-6);
	float sc = px_per_uv / DESIGN;

	float R = sphere_radius;
	vec2 d = UV * DESIGN - sphere_center;
	float dist_from_center = length(d);
	float disk = clamp((R - dist_from_center) * sc + 0.5, 0.0, 1.0);

	vec2 vxy = vec2(d.x, -d.y) / R;
	float zz = sqrt(max(0.0, 1.0 - dot(vxy, vxy)));
	float rot = time_val * rotation_speed;
	float lat_off = fract(time_val * latitude_speed / PI);

	vec3 col = vec3(0.0);
	float a = 0.0;

	// 1. Optional sphere fill. Transparent by default.
	vec2 q = d / R;
	float g = clamp(length(q - vec2(-55.0, -65.0) / 163.0) / 1.25, 0.0, 1.0);
	over(col, a, vec3(mix(0.067, 0.016, g)), fill_opacity * disk);

	// 2. Back and front latitude / longitude grids.
	float ab = grid_alpha(vec3(vxy, -zz), rot, lat_off, sc, false);
	float af = grid_alpha(vec3(vxy, zz), rot, lat_off, sc, true);
	float grid = 1.0 - (1.0 - ab) * (1.0 - af);
	over(col, a, tint, grid * disk);

	// 3. Surface marker at 24 N, 35 E.
	float mlat = radians(24.0);
	float mlon = radians(35.0);
	vec3 mp = project(
		vec3(cos(mlat) * sin(mlon), sin(mlat), cos(mlat) * cos(mlon)),
		rot
	);
	float marker_dist = length(d - vec2(mp.x, -mp.y) * R);
	over(
		col,
		a,
		tint,
		line_a(marker_dist - 1.4, 2.8, sc) * step(0.0, mp.z) * disk
	);

	// 4. Sphere outline and four cardinal tick marks.
	over(col, a, tint, line_a(abs(dist_from_center - R), 1.7, sc) * 0.55);
	vec2 ad = abs(d);
	float tick = min(
		sd_seg(ad, vec2(R - 4.0, 0.0), vec2(R + 9.0, 0.0)),
		sd_seg(ad, vec2(0.0, R - 4.0), vec2(0.0, R + 9.0))
	);
	over(col, a, tint, line_a(tick, 1.8, sc) * 0.85);

	// 5. Dashed crosshair and fading trail, clipped to the sphere.
	float clip_mask = clamp((R - 1.0 - dist_from_center) * sc + 0.5, 0.0, 1.0);
	vec2 dc = d - cursor_pos;
	float dash_h = step(fract((d.x + R) / 9.0), 3.0 / 9.0);
	float dash_v = step(fract((d.y + R) / 9.0), 3.0 / 9.0);
	float cross_a = max(
		line_a(abs(dc.y), 0.9, sc) * dash_h,
		line_a(abs(dc.x), 0.9, sc) * dash_v
	) * 0.22;
	over(col, a, tint, cross_a * clip_mask);

	float trail_a = 0.0;
	for (int i = 1; i < TRAIL_LEN; i++) {
		vec3 pa = trail[i - 1];
		vec3 pb = trail[i];
		trail_a = max(
			trail_a,
			line_a(sd_seg(d, pa.xy, pb.xy), 1.8, sc) * pb.z * 0.5
		);
	}
	over(col, a, tint, trail_a * clip_mask);

	// 6. Cursor crosshair ticks, pulse and corner brackets.
	vec2 ac = abs(dc);
	float cross_tick = min(
		sd_seg(ac, vec2(6.0, 0.0), vec2(14.0, 0.0)),
		sd_seg(ac, vec2(0.0, 6.0), vec2(0.0, 14.0))
	);
	over(col, a, tint, line_a(cross_tick, 2.1, sc));
	over(col, a, tint, line_a(length(dc) - 1.4, 2.8, sc));

	float pulse = (sin(time_val * 3.2) + 1.0) * 0.5;
	float bracket = 13.0 + pulse * 2.0;
	float bracket_dist = min(
		sd_seg(ac, vec2(bracket, bracket - 4.0), vec2(bracket, bracket)),
		sd_seg(ac, vec2(bracket - 4.0, bracket), vec2(bracket, bracket))
	);
	over(
		col,
		a,
		tint,
		line_a(bracket_dist, 1.2, sc) * (0.45 + pulse * 0.35)
	);

	// 7. Leader line accent.
	vec2 p0 = cursor_pos + vec2(16.0, 0.0);
	vec2 p1 = cursor_pos + vec2(22.0, -21.0);
	vec2 p2 = cursor_pos + vec2(27.0, -21.0);
	float leader_dist = min(sd_seg(d, p0, p1), sd_seg(d, p1, p2));
	over(col, a, tint, line_a(leader_dist, 1.1, sc) * 0.8);

	COLOR = vec4(col, a);
}
