shader_type canvas_item;
// Procedural animated space backdrop for the main menu: a deep-space gradient,
// drifting nebula clouds, and a field of twinkling stars. Resolution
// independent and fully TIME-driven, so no texture or per-frame script work.

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;

	// Deep space base with a subtle vertical gradient.
	vec3 col = mix(vec3(0.012, 0.018, 0.04), vec3(0.028, 0.045, 0.09), uv.y);

	// Drifting nebula clouds (teal + purple).
	float n = sin(uv.x * 4.0 + TIME * 0.03) * sin(uv.y * 6.0 - TIME * 0.02)
			+ sin((uv.x + uv.y * 0.7) * 8.0 + TIME * 0.04);
	float neb = smoothstep(0.2, 1.0, n * 0.5 + 0.5);
	col += vec3(0.09, 0.17, 0.3) * neb;
	col += vec3(0.24, 0.12, 0.36) * smoothstep(0.55, 1.0, n * 0.5 + 0.5) * 0.5;

	// Common small stars, each twinkling at its own phase.
	vec2 cell = floor(uv * vec2(90.0, 60.0));
	float r = hash21(cell);
	float tw = 0.55 + 0.45 * sin(TIME * (1.5 + r * 5.0) + cell.x * 13.0 + cell.y * 7.0);
	float star = step(0.99, r) * tw;
	col += vec3(0.75, 0.88, 1.0) * star;

	// Rare brighter warm stars.
	float r2 = hash21(cell + vec2(31.7, 17.3));
	float tw2 = 0.5 + 0.5 * sin(TIME * (2.0 + r2 * 3.0) + cell.y * 11.0);
	float star2 = step(0.997, r2) * tw2;
	col += vec3(1.0, 0.92, 0.8) * star2 * 1.4;

	COLOR = vec4(col, 1.0);
}
