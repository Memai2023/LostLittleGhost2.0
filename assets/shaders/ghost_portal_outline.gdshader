shader_type canvas_item;

// Warm outline for the checkpoint portal-pose reaction only -- ghost-portal.png
// is close in hue to the checkpoint's own blue portal glow, so this separates
// the two on screen. Applied as a dedicated ShaderMaterial only while
// is_showing_portal_pose is true (see player.gd show_portal_pose()/
// clear_portal_pose()); the sprite's original material is restored the moment
// the reaction ends, so no other pose is ever affected.
//
// Standard fixed-radius ring outline: for every pixel, sample the texture at
// several points around a circle of radius outline_width_px (in *source
// texture* pixels) and take the strongest alpha found. That coverage is
// blended under the pixel's own (unmodified) color, so fully opaque artwork
// stays exactly as painted and only the surrounding transparent halo picks up
// the outline color. outline_width_px is set from GDScript as
// target_screen_px / portal_pose_scale, so the rendered ring stays a
// consistent screen-pixel thickness regardless of the sprite's own scale.

uniform vec4 outline_color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform float outline_width_px = 25.5;

const int SAMPLES = 16;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec2 offset_unit = TEXTURE_PIXEL_SIZE * outline_width_px;

	float outline_alpha = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		float angle = (float(i) / float(SAMPLES)) * 2.0 * PI;
		vec2 offset = vec2(cos(angle), sin(angle)) * offset_unit;
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + offset).a);
	}

	vec4 outline = vec4(outline_color.rgb, outline_color.a * outline_alpha);
	COLOR = mix(outline, tex_color, tex_color.a);
}
