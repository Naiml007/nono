shader_type canvas_item;
// A transparent, resolution-independent star plane. Nebula and planetary forms
// live in the authored background plate underneath, leaving this layer to add
// only distant twinkle. TIME keeps the animation self-contained and inexpensive.

uniform float star_density : hint_range(0.0, 0.03) = 0.008;
uniform float star_opacity : hint_range(0.0, 0.6) = 0.17;
uniform float star_drift : hint_range(0.0, 0.1) = 0.012;
uniform float star_scale : hint_range(0.5, 2.0) = 1.0;
uniform float motion_scale : hint_range(0.0, 1.0) = 1.0;
uniform vec2 field_offset = vec2(0.0);
uniform vec2 parallax_uv_offset = vec2(0.0);
uniform float horizontal_crop : hint_range(0.0, 0.5) = 0.0;
uniform float horizontal_expand : hint_range(0.0, 1.0) = 1.0;
uniform float horizontal_offset : hint_range(0.0, 0.5) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	uv.x = uv.x * horizontal_expand + horizontal_offset;
	uv += parallax_uv_offset + vec2(TIME * star_drift, TIME * star_drift * 0.42) * motion_scale + field_offset;
	vec2 star_uv = uv * star_scale;
	vec2 cell = floor(star_uv * vec2(128.0, 72.0));
	vec2 local = fract(star_uv * vec2(128.0, 72.0));
	float seed = hash21(cell);
	float phase = TIME * motion_scale * (0.7 + seed * 1.4) + cell.x * 17.0 + cell.y * 9.0;
	float twinkle = 0.65 + 0.35 * sin(phase);
	float star = step(1.0 - star_density, seed);
	float core = 1.0 - smoothstep(0.02, 0.11, length(local - vec2(0.5)));
	float intensity = star * core * twinkle * star_opacity;
	COLOR = vec4(vec3(0.68, 0.84, 1.0), intensity);
}
