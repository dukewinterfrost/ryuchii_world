shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 day_night_tint : source_color = vec4(1.0);

uniform vec4 grass_light : source_color = vec4(0.42, 0.60, 0.22, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.16, 0.32, 0.15, 1.0);
uniform vec4 path_color : source_color = vec4(0.65, 0.47, 0.24, 1.0);
uniform float pixel_density = 12.0;
varying vec2 ground_position;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patch_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),f.x),
		mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0)),f.x),f.y);
}
void vertex() { ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	vec2 p = floor(ground_position * pixel_density) / pixel_density;
	float patches = patch_noise(p * 0.7);
	float flecks = hash21(floor(p * pixel_density));
	float path_center = 20.5 + sin(p.y * 0.19) * 1.7;
	float edge = abs(p.x-path_center) - (1.6 + sin(p.y*0.32)*0.25);
	// A wider, irregular oval at the companion's resting area echoes the
	// surrounding grove rather than reinforcing a north/south strip.
	vec2 clearing_delta = (p-vec2(20.5,24.5))/vec2(6.2,3.7);
	float clearing = (length(clearing_delta)-1.0)*3.7;
	float dirt = 1.0-smoothstep(-0.16,0.32,min(edge,clearing)+patches*0.42);
	vec3 grass = mix(grass_dark.rgb, grass_light.rgb, 0.42+patches*0.58);
	grass += (step(0.94,flecks)-0.04)*0.055;
	vec3 soil = path_color.rgb*(0.91+patches*0.16)+(flecks-0.5)*0.025;
	// Painted, stationary leaf-shadow pools: no temporal noise/pixel swimming.
	float shade = smoothstep(0.49,0.69,patch_noise(p*0.24+vec2(8.0,3.0)));
	float sun = 1.0-shade*0.24;
	ALBEDO = mix(grass,soil,dirt)*sun*day_night_tint.rgb;
}
