shader_type canvas_item;
render_mode blend_add;

// Door-proximity sunrise: a soft rising sun near the right horizon, with a
// wide warm glow and a handful of broad atmospheric rays fanning up and to
// the left from it, plus the existing gentle sky brightening. The disc,
// the glow, and every ray are all measured from the single shared
// `sun_position` uniform in the same aspect-corrected coordinate space, so
// the rays always visibly originate at the sun and the sun stays circular
// regardless of the viewport's aspect ratio (1920x1080 or otherwise).
//
// `intensity` (driven from door_sunrise.gd, smoothed there frame to frame)
// is the master fade -- sun, glow and rays all scale with it and vanish
// together at 0, exactly like the sky brightening already did. Nothing in
// this shader reads distance/progress itself.
//
// Uses SCREEN_UV (true screen-space 0..1) rather than the Polygon2D's own
// UV -- Polygon2D only interpolates its `uv` array when a texture is
// assigned, so with no texture (as here) the builtin UV stays (0,0) for
// every pixel. The quad is already built and repositioned every frame to
// exactly cover the viewport (see door_sunrise.gd), so SCREEN_UV lines up
// with it perfectly with no extra bookkeeping.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sunrise_color : source_color = vec4(1.0, 0.72, 0.4, 1.0);
uniform float max_sky_brightness : hint_range(0.0, 2.0) = 0.75;
uniform vec4 ray_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float max_ray_opacity : hint_range(0.0, 1.0) = 0.28;
uniform float ray_speed : hint_range(0.0, 2.0) = 0.06;

// Shared origin for the sun disc, its glow, and every ray -- see header
// comment. In SCREEN_UV space (0,0 = top-left, 1,1 = bottom-right).
uniform vec2 sun_position = vec2(0.86, 0.62);
uniform float sun_radius : hint_range(0.0, 0.3) = 0.05;
uniform float sun_softness : hint_range(0.0, 0.3) = 0.05;
uniform float sun_glow_radius : hint_range(0.0, 1.0) = 0.32;
uniform float sun_intensity : hint_range(0.0, 3.0) = 1.3;

uniform float ray_length : hint_range(0.0, 1.5) = 0.55;
uniform float ray_width : hint_range(0.0, 0.5) = 0.05;
uniform float ray_spread : hint_range(0.0, 3.14159265) = 1.7;
uniform float ray_count : hint_range(1.0, 10.0) = 6.0;

const int MAX_RAYS = 10;
// Fan center points up and to the left (negative x, negative y -- screen Y
// increases downward, so negative y is physically "up").
const float RAY_BASE_ANGLE = -2.35619449; // radians(-135.0)

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Shared aspect correction: normalizes x by the viewport's aspect ratio
	// so distances/angles measured from sun_position are physically
	// correct (a circle stays a circle, rays radiate evenly) at any
	// resolution. Used identically below by the sun disc, its glow, and
	// every ray.
	vec2 aspect_correction = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 to_sun = (uv - sun_position) * aspect_correction;
	float dist_to_sun = length(to_sun);

	// Sky brightening: strongest low in the frame (near the horizon) and
	// toward the right (near the sun), fading smoothly upward and to the
	// left -- never a flat full-screen tint.
	float horizon_falloff = smoothstep(0.25, 1.0, uv.y);
	float side_falloff = smoothstep(0.0, 1.0, uv.x);
	float sky_amount = horizon_falloff * mix(0.55, 1.0, side_falloff);
	float sky_strength = sky_amount * max_sky_brightness * intensity;
	vec3 sky_glow = sunrise_color.rgb * sky_strength;

	// Sun disc + glow: a soft bright core (no hard edge -- smoothstep does
	// all the falloff) plus a much wider, dimmer halo band around it. Core
	// blends toward a pale near-white at the very center, and toward the
	// warmer sunrise_color further out, so it reads as "pale-gold with a
	// bright center" rather than a flat white circle.
	float sun_core = smoothstep(sun_radius + sun_softness, max(sun_radius - sun_softness, 0.0), dist_to_sun);
	float sun_halo = smoothstep(sun_glow_radius, sun_radius, dist_to_sun) * (1.0 - sun_core);
	float sun_brightness = (sun_core + sun_halo * 0.4) * sun_intensity * intensity;
	// Center stays a warm pale gold rather than blending toward neutral
	// white, so the disc reads as "sun" even at its brightest point instead
	// of clipping to a flat white circle.
	vec3 sun_rgb = mix(sunrise_color.rgb, vec3(1.0, 0.92, 0.7), clamp(sun_core, 0.0, 1.0));
	vec3 sun_light = sun_rgb * sun_brightness;

	// Rays: a handful of broad, soft, slightly-irregular beams fanning up
	// and to the left from sun_position -- built in each ray's own local
	// (along, across) frame so width/length fall off as real distances
	// rather than an angular wedge (an angular-only falloff would widen
	// forever with distance and look like a spotlight cone). Combined with
	// max() rather than a sum so overlapping rays don't blow out and the
	// gaps between rays stay visible.
	int ray_n = clamp(int(ray_count), 1, MAX_RAYS);
	float rays_shape = 0.0;
	for (int i = 0; i < MAX_RAYS; i++) {
		if (i >= ray_n) {
			break;
		}
		float fi = float(i);
		float h1 = hash11(fi * 3.17 + 1.0);
		float h2 = hash11(fi * 5.71 + 4.0);
		float h3 = hash11(fi * 9.13 + 7.0);

		float spread_t = ray_n > 1 ? (fi / float(ray_n - 1) - 0.5) : 0.0;
		float base_angle = RAY_BASE_ANGLE + spread_t * ray_spread;
		// Extremely slow drift/pulse -- the origin itself never moves,
		// only each ray's angle and brightness wobble very gently.
		float drift = sin(TIME * ray_speed * 0.3 + fi * 1.7) * 0.03;
		float this_angle = base_angle + (h1 - 0.5) * 0.12 + drift;
		float this_width = ray_width * (0.7 + h2 * 0.6);
		float this_length = ray_length * (0.75 + h3 * 0.5);
		float this_strength = 0.6 + h1 * 0.5;

		vec2 dir = vec2(cos(this_angle), sin(this_angle));
		vec2 perp = vec2(-dir.y, dir.x);
		float along = dot(to_sun, dir);
		float across = dot(to_sun, perp);

		float along_norm = clamp(along / max(this_length, 0.001), 0.0, 1.0);
		// Fades in just past the sun (avoids a hard start at the origin),
		// stays visibly bright for most of the ray's length, and only
		// tapers off in the final stretch toward the tip -- pow() biases
		// the falloff to hold longer than a linear fade would.
		float length_fade = (1.0 - pow(along_norm, 1.6)) * smoothstep(0.0, 0.06, along);
		float local_half_width = this_width * (1.0 + along_norm * 0.7);
		float width_fade = 1.0 - smoothstep(0.0, local_half_width, abs(across));

		float pulse = 0.85 + 0.15 * sin(TIME * ray_speed + fi * 2.1);
		float this_ray = length_fade * width_fade * this_strength * pulse;
		rays_shape = max(rays_shape, this_ray);
	}
	float ray_strength = rays_shape * max_ray_opacity * intensity;
	vec3 rays = ray_color.rgb * ray_strength;

	vec3 final_color = sky_glow + sun_light + rays;
	float final_alpha = clamp(sky_strength + sun_brightness * 0.5 + ray_strength, 0.0, 1.0);

	COLOR = vec4(final_color, final_alpha);
}
