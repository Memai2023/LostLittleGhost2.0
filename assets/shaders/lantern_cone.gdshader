shader_type canvas_item;

// Soft directional light-cone fill: brightest near the origin (the
// lantern), fading outward along its length in a clear, continuous
// gradient rather than a flat fill -- a fast initial drop from the
// lantern leveling into a long, low-opacity tail that stays visible all
// the way to the far edge, so the player can read the danger distance
// instead of seeing a solid flat triangle. Purely visual -- the gameplay
// detection Area2D/CollisionPolygon2D this mirrors is untouched and stays
// invisible.

uniform float cone_length = 260.0;
uniform float cone_width = 160.0;
uniform vec4 warm_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);

// Alpha at the lantern origin, the cone's mid-length body, and its far
// edge. The body value falls out of the falloff curve below rather than
// being set directly -- see FALLOFF_POWER.
const float ORIGIN_ALPHA = 0.6;
const float EDGE_ALPHA = 0.15;
// <1 = fast drop right after the origin, leveling out toward the edge
// (roughly real lantern falloff) instead of a straight linear fade.
const float FALLOFF_POWER = 0.35;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float dist_t = clamp(local_pos.x / max(cone_length, 1.0), 0.0, 1.0);
	float half_width_at_x = max((cone_width * 0.5) * dist_t, 0.001);
	float edge_t = abs(local_pos.y) / half_width_at_x;

	float falloff = 1.0 - pow(dist_t, FALLOFF_POWER);
	float length_alpha = EDGE_ALPHA + (ORIGIN_ALPHA - EDGE_ALPHA) * falloff;

	// Soft feather toward the two side edges so the cone doesn't read as
	// a hard-edged flat triangle.
	float edge_fade = 1.0 - smoothstep(0.75, 1.0, edge_t);

	float alpha = length_alpha * edge_fade;
	COLOR = vec4(warm_color.rgb, alpha * warm_color.a);
}
