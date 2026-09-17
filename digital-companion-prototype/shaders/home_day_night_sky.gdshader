shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D artwork : source_color, filter_nearest;
uniform bool is_panorama = false;
uniform bool preserve_artwork = false;
uniform vec4 scenery_tint : source_color = vec4(1.0);
uniform vec4 sky_top : source_color;
uniform vec4 sky_horizon : source_color;
uniform vec2 sun_position;
uniform vec2 moon_position;
uniform float sun_visibility = 0.0;
uniform float moon_visibility = 0.0;
uniform float star_visibility = 0.0;

void vertex() {
	// Retain the authored card's scale and pivot while matching Sprite3D billboard.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 sky(vec2 uv, float aspect) {
	vec2 pixel = floor(uv * vec2(480.0, 270.0)) / vec2(480.0, 270.0);
	float band = floor(clamp(pixel.y, 0.0, 1.0) * 24.0) / 24.0;
	vec3 color = mix(sky_top.rgb, sky_horizon.rgb, band);
	vec2 cell = floor(pixel * vec2(480.0, 270.0));
	float star = step(0.997, hash21(cell)) * (1.0 - smoothstep(0.4, 0.9, pixel.y));
	color = mix(color, vec3(0.79, 0.87, 1.0), star * star_visibility * 0.8);
	vec2 sun_delta = (pixel - sun_position) * vec2(aspect, 1.0);
	float sun_disc = 1.0 - step(0.041, length(sun_delta));
	float halo = (1.0 - smoothstep(0.041, 0.095, length(sun_delta))) * 0.14;
	color = mix(color, vec3(1.0, 0.85, 0.51), max(sun_disc, halo) * sun_visibility);
	vec2 moon_delta = (pixel - moon_position) * vec2(aspect, 1.0);
	float moon_disc = 1.0 - step(0.036, length(moon_delta));
	float crater = step(length(moon_delta - vec2(-0.011, -0.006)), 0.009)
		+ step(length(moon_delta - vec2(0.014, 0.013)), 0.006);
	vec3 moon_color = mix(vec3(0.89, 0.94, 1.0), vec3(0.66, 0.77, 0.9), min(crater, 1.0) * 0.4);
	color = mix(color, moon_color, moon_disc * moon_visibility);
	return color;
}

float clear_sky(vec3 color) {
	return smoothstep(0.025, 0.06, color.b - color.g)
		* smoothstep(0.08, 0.16, color.g - color.r);
}

void fragment() {
	// One distant sky across both cards; camera motion cannot create a seam or
	// a second moon. The arc occupies the upper 28% of the world viewport.
	vec2 sky_uv = vec2(SCREEN_UV.x, SCREEN_UV.y / 0.28);
	float sky_aspect = VIEWPORT_SIZE.x / (VIEWPORT_SIZE.y * 0.28);
	if (preserve_artwork) {
		vec4 source = texture(artwork, UV);
		// Retain BG-1 clouds and mountains. Cool/dim the painted clear sky at
		// night, retaining bright readable silhouettes without new raster art.
		float opening = (1.0 - smoothstep(0.35, 0.62, UV.y)) * clear_sky(source.rgb);
		vec3 painted = source.rgb * scenery_tint.rgb;
		ALBEDO = mix(painted, sky(sky_uv, sky_aspect), opening * (0.25 + star_visibility * 0.55));
	} else if (is_panorama) {
		vec4 source = texture(artwork, UV);
		// The source panorama contains an opaque cyan sky. Key only its upper
		// clear-sky opening; dark canopy, clouds and mountain silhouettes survive.
		float cyan = clear_sky(source.rgb);
		// Remove small painted white stars surrounded by clear sky, so all stars
		// obey the clock. Large clouds and dark tree details remain artwork.
		vec2 step_uv = vec2(4.0) / vec2(textureSize(artwork, 0));
		float around = min(min(clear_sky(texture(artwork, UV + vec2(step_uv.x, 0.0)).rgb),
			clear_sky(texture(artwork, UV - vec2(step_uv.x, 0.0)).rgb)),
			min(clear_sky(texture(artwork, UV + vec2(0.0, step_uv.y)).rgb),
			clear_sky(texture(artwork, UV - vec2(0.0, step_uv.y)).rgb)));
		cyan = max(cyan, around * step(0.45, min(source.r, min(source.g, source.b))));
		float opening = 1.0 - smoothstep(0.17, 0.27, UV.y);
		float mask = max(cyan * opening, 1.0 - smoothstep(0.0, 0.08, UV.y));
		ALBEDO = mix(source.rgb * scenery_tint.rgb, sky(sky_uv, sky_aspect), mask);
	} else {
		ALBEDO = sky(sky_uv, sky_aspect);
	}
}
