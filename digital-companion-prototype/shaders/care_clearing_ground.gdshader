shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 day_night_tint : source_color = vec4(1.0);

uniform vec4 grass_light : source_color = vec4(0.42, 0.60, 0.22, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.16, 0.32, 0.15, 1.0);
uniform vec4 path_color : source_color = vec4(0.65, 0.47, 0.24, 1.0);
uniform float pixel_density = 12.0;
uniform float lower_shadow_strength : hint_range(0.0, 1.0) = 0.62;
uniform float meadow_warmth : hint_range(0.0, 1.0) = 0.55;
uniform float grass_detail : hint_range(0.0, 1.0) = 0.8;
uniform vec4 tree_shadows[12];
varying vec2 ground_position;
varying float ground_height;
varying float cliff_face;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patch_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),f.x),
		mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0)),f.x),f.y);
}
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_position = world.xz;
	ground_height = world.y;
	cliff_face = 1.0-abs(NORMAL.y);
}
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
	float path_chips = (patch_noise(p * 3.1) - 0.5) * 0.7;
	float dirt = 1.0-smoothstep(-0.10,0.19,min(edge,clearing)+patches*0.42+path_chips);
	// The path belongs to the level clearing, not an endless stripe down the valley.
	dirt *= 1.0 - smoothstep(0.5, 6.0, -ground_height);
	vec3 grass = mix(grass_dark.rgb, grass_light.rgb, 0.42+patches*0.58);
	grass += (step(0.94,flecks)-0.04)*0.055;
	// Warm meadow patches and tiny painted grass groups echo the reference's
	// textured clearing. World-space quantization keeps every mark stationary.
	float plateau = 1.0 - smoothstep(0.0, 2.0, -ground_height);
	float meadow = smoothstep(0.28, 0.73, patch_noise(p * 0.16 + vec2(5.0, 19.0)));
	grass = mix(grass, vec3(0.60, 0.65, 0.26), meadow * meadow_warmth * plateau);
	vec2 tuft_grid = p + vec2(patch_noise(p * 0.27) * 0.4, patch_noise(p * 0.22 + vec2(7.0)) * 0.65);
	vec2 tuft_cell = floor(tuft_grid);
	vec2 tuft_uv = fract(tuft_grid);
	float tuft_seed = hash21(tuft_cell + vec2(11.0, 3.0));
	float tuft = 0.0;
	for (int stem = 0; stem < 3; stem++) {
		float n = hash21(tuft_cell + vec2(float(stem) * 7.0, 13.0));
		float x = 0.22 + float(stem) * 0.23 + (n - 0.5) * 0.13;
		float base = 0.08 + tuft_seed * 0.26;
		tuft = max(tuft, (1.0-step(0.048, abs(tuft_uv.x-x))) * step(base, tuft_uv.y) * (1.0-step(base+0.2+n*0.42, tuft_uv.y)));
	}
	grass += tuft * step(0.56, tuft_seed) * grass_detail * plateau * vec3(0.11, 0.10, 0.024);
	vec3 soil = path_color.rgb*(0.91+patches*0.16)+(flecks-0.5)*0.025;
	// Painted, stationary leaf-shadow pools: no temporal noise/pixel swimming.
	float shade = smoothstep(0.49,0.69,patch_noise(p*0.24+vec2(8.0,3.0)));
	float sun = 1.0-shade*0.24;
	vec3 ground_color = mix(grass,soil,dirt)*sun;
	// Art-directed shade: the lower shoulder recedes, but the playable plateau
	// stays bright. This is stable painted shade, not a real-time light/shadow rig.
	float lower = smoothstep(0.7, 10.0, -ground_height);
	float woodland = 0.88 + patch_noise(p * 0.12 + vec2(13.0, 4.0)) * 0.12;
	ground_color *= mix(vec3(1.0), vec3(0.64, 0.77, 0.73) * (1.0-lower_shadow_strength) * woodland, lower);
	for (int i = 0; i < 12; i++) {
		vec4 tree = tree_shadows[i];
		if (tree.z > 0.0) {
			float d = length((p-tree.xy-vec2(0.5, 0.65))/vec2(tree.z, tree.z*0.72));
			float canopy = (1.0-smoothstep(0.16, 1.0, d)) * (0.8+patch_noise(p*1.6)*0.2);
			ground_color *= 1.0-canopy*tree.w;
		}
	}
	// Sheer earthen wall, with stationary horizontal strata and a dark base.
	float strata = patch_noise(vec2(p.x*0.24+p.y*0.17, floor(ground_height*5.0)*0.18));
	vec3 cliff = mix(vec3(0.085,0.13,0.085),vec3(0.20,0.235,0.13),strata);
	cliff *= mix(1.0,0.60,smoothstep(0.0,16.0,-ground_height));
	ALBEDO = mix(ground_color,cliff,cliff_face)*day_night_tint.rgb;
}
