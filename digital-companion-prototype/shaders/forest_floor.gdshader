shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D source_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 source_region = vec4(760.0, 700.0, 40.0, 22.0);
uniform vec2 tile_meters = vec2(5.0, 3.0);
varying vec2 ground_position;
void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	// Mirrored UVs meet at identical edge texels, including between mesh chunks.
	vec2 cell = ground_position / max(tile_meters, vec2(0.1));
	vec2 mirrored = 1.0 - abs(mod(cell, 2.0) - 1.0);
	vec2 source_size = vec2(textureSize(source_texture, 0));
	vec2 pixel = source_region.xy + vec2(0.5) + mirrored * (source_region.zw - vec2(1.0));
	vec3 grass = texture(source_texture, pixel / source_size).rgb;
	float shade = 0.86 + 0.08 * sin(ground_position.x * 0.18) * cos(ground_position.y * 0.16);
	ALBEDO = mix(vec3(0.20, 0.38, 0.12), grass, 0.72) * shade;
}
