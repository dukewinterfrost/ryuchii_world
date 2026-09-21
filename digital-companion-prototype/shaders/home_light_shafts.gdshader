shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 shaft_color : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float lean = -3.0;
uniform float animation_time = 0.0;
uniform float phase = 0.0;

void vertex() {
	// Rooted camera-facing ribbons. Widen toward the forest floor, and keep
	// ordinary depth testing so trees and actors can occlude the light.
	VERTEX.x *= mix(0.35, 1.0, UV.y);
	VERTEX.x += lean * (1.0 - UV.y);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float feather = 1.0 - smoothstep(0.12, 1.0, across);
	float ends = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	float strands = 0.82 + 0.18 * sin(UV.x * 34.0 + phase);
	float shimmer = 0.96 + 0.04 * sin(animation_time * 0.35 + phase + UV.y * 3.0);
	ALBEDO = shaft_color.rgb;
	ALPHA = feather * ends * strands * shimmer * strength;
}
