shader_type canvas_item;

// Soft directional light-cone fill: brightest near the origin (the
// lantern), fading outward along its length, and feathered toward its two
// side edges instead of a hard triangle boundary. Purely visual -- the
// gameplay detection Area2D/CollisionPolygon2D this mirrors is untouched
// and stays invisible.

uniform float cone_length = 260.0;
uniform float cone_width = 160.0;
uniform vec4 warm_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float dist_t = clamp(local_pos.x / max(cone_length, 1.0), 0.0, 1.0);
	float half_width_at_x = max((cone_width * 0.5) * dist_t, 0.001);
	float edge_t = abs(local_pos.y) / half_width_at_x;
	// Minimal gradient: the cone is essentially flat (constant alpha) across
	// 90% of its length and width, with only a thin, crisp feather in the
	// outer 10% so the far/side edges read as clearly defined rather than
	// gradually dissolving. Combined with a lower base warm_color alpha,
	// this gives a low/moderate-opacity, clearly-bounded danger area.
	float edge_fade = 1.0 - smoothstep(0.9, 1.0, edge_t);
	float length_fade = 1.0 - smoothstep(0.9, 1.0, dist_t);
	float alpha = length_fade * edge_fade;
	COLOR = vec4(warm_color.rgb, alpha * warm_color.a);
}
