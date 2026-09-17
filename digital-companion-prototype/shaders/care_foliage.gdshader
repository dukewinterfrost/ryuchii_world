shader_type spatial;
render_mode unshaded;
uniform vec4 day_night_tint : source_color = vec4(1.0);
uniform vec4 base_color : source_color = vec4(0.22,0.43,0.17,1.0);
varying vec3 world_normal;
void vertex() { world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL); }
void fragment() {
	float facing = dot(normalize(world_normal),normalize(vec3(-0.6,1.0,0.4)));
	float bands = floor(clamp(facing*0.5+0.5,0.0,1.0)*4.0)/4.0;
	ALBEDO = base_color.rgb*(0.67+bands*0.48)*day_night_tint.rgb;
}
