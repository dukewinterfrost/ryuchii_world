shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 day_night_tint : source_color = vec4(1.0);
uniform bool reduced_motion = false;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 vec2 p = floor(local_position.xz * 18.0) / 18.0;
 float t = reduced_motion ? 0.0 : TIME * 0.32;
 float r = length(p * vec2(0.7, 1.0));
 float ripple = step(0.97, sin(r * 12.0 - t * 2.0)) * step(0.35, sin(atan(p.y,p.x)*7.0+r*2.0)) * 0.045;
 float shimmer = step(0.86, sin(p.x*9.0+t)*cos(p.y*13.0-t)) * 0.035;
 vec3 deep = vec3(0.16,0.43,0.43);
 vec3 shallow = vec3(0.35,0.65,0.61);
 ALBEDO = (mix(deep, shallow, smoothstep(0.1,2.5,r)) + ripple + shimmer) * day_night_tint.rgb;
}
