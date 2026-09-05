shader_type canvas_item;
// Shared actor rim shader for NONO. Gives every gameplay sprite a bright,
// tuneable 1-2px outline plus a subtle interior rim glow so actors pop
// against the dark navy arena backdrop regardless of where they sit.
//
// Works in UV space, so it is independent of sprite scale and texture
// resolution.
//
// Modulate handling: in the Compatibility renderer the fragment `COLOR` input
// already equals `texture * modulate`, so multiplying the output by it would
// square the texture (darkening). We capture the *pure* modulate in the vertex
// shader (no texture multiply happens there) via a varying instead, so hurt
// flashes, boss telegraph tints, invulnerability flicker and power-up type
// tints keep working unchanged.

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.25; // in texels
uniform float glow : hint_range(0.0, 1.0) = 0.45;          // interior rim glow strength
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35; // alpha treated as "solid"

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;

	// Max neighbour alpha in 8 directions -> tells us where the silhouette is.
	float na = 0.0;
	na = max(na, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
	na = max(na, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	na = max(na, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	na = max(na, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	na = max(na, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);
	na = max(na, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	na = max(na, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	na = max(na, texture(TEXTURE, UV + vec2(px.x, px.y)).a);

	bool solid = a >= alpha_threshold;
	bool near_solid = na >= alpha_threshold;

	vec4 col = tex;
	// Bright halo ring just outside the silhouette.
	if (!solid && near_solid) {
		col = vec4(outline_color.rgb, outline_color.a);
	}
	// Subtle additive rim glow hugging the inside edge of solid pixels.
	float inside_edge = float(solid && !near_solid);
	col.rgb += outline_color.rgb * inside_edge * glow * 0.5;

	col *= v_mod;
	COLOR = col;
}
