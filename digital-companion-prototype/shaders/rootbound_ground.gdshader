shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D source_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 source_region = vec4(760.0, 700.0, 40.0, 22.0);
uniform vec2 field_center = vec2(15.0, 18.0);
uniform vec2 clearing_radii = vec2(13.4, 11.0);
uniform vec4 grass_light : source_color = vec4(0.43, 0.58, 0.24, 1.0);
uniform vec4 soil_color : source_color = vec4(0.57, 0.45, 0.26, 1.0);
uniform float source_detail : hint_range(0.0, 1.0) = 0.18;
uniform float lower_shadow_strength : hint_range(0.0, 1.0) = 0.62;
uniform float pixel_density = 12.0;
varying vec3 world_position;
varying float cliff_face;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise21(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),f.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0)),f.x),f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cliff_face = 1.0-abs(NORMAL.y);
}
void fragment() {
	vec2 p = floor(world_position.xz * pixel_density) / pixel_density;
	float patch = noise21(p * 0.38);
	float fine = hash21(floor(p * pixel_density));
	// Sample only the bound forest grass patch, never the panorama's trees/sky.
	vec2 cell = floor(p / vec2(4.8, 3.6));
	vec2 uv = fract(p / vec2(4.8, 3.6));
	if (hash21(cell) > 0.5) { uv.x = 1.0-uv.x; }
	vec2 texel = source_region.xy + floor(uv * (source_region.zw-1.0)) + 0.5;
	vec3 source = texture(source_texture, texel / vec2(textureSize(source_texture,0))).rgb;
	vec3 grass = grass_light.rgb * (0.78 + patch*0.28);
	grass = mix(grass, source, source_detail);
	// An irregular worn clearing, not a painted combat boundary or collider.
	vec2 d = (p-field_center-vec2(0.0,2.0)) / clearing_radii;
	float edge = length(d) + (noise21(p*0.75)-0.5)*0.11;
	float dirt = (1.0-smoothstep(0.70,1.04,edge)) * (0.72+patch*0.20);
	dirt *= 1.0-smoothstep(0.3,3.0,-world_position.y);
	vec3 soil = soil_color.rgb * (0.90+patch*0.13) + (fine-0.5)*0.016;
	vec3 color = mix(grass,soil,dirt);
	float fleck = step(0.977, fine) * (1.0-dirt) * 0.045;
	color += vec3(fleck, fleck, 0.0);
	// Stationary painted canopy shade beneath the existing (15,9) blocker.
	float tree = length((p-vec2(15.4,9.8))/vec2(3.5,2.0));
	color *= 1.0-(1.0-smoothstep(0.1,1.0,tree))*0.29;
	float shade = smoothstep(0.7,8.0,-world_position.y);
	color *= mix(vec3(1.0), vec3(0.64,0.77,0.73)*(1.0-lower_shadow_strength),shade);
	float strata = noise21(vec2(p.x*0.24+p.y*0.17,floor(world_position.y*5.0)*0.18));
	vec3 cliff = mix(vec3(0.085,0.13,0.085),vec3(0.20,0.235,0.13),strata);
	cliff *= mix(1.0,0.60,smoothstep(0.0,12.0,-world_position.y));
	ALBEDO = mix(color,cliff,cliff_face);
}
