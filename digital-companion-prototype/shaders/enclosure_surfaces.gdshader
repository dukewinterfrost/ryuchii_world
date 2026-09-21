shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 day_night_tint : source_color = vec4(1.0);
varying vec3 model_position;
varying vec4 palette_color;
void vertex() { model_position = VERTEX; palette_color = COLOR; }
float hash(vec3 p) { return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453); }
void fragment() {
 vec3 c = palette_color.rgb;
 vec3 p = floor(model_position * 22.0);
 float grain = (hash(p)-0.5)*0.065;
 bool timber = c.r > c.g*1.15 && c.g > c.b*1.13;
 if(timber) grain += (hash(vec3(floor(p.x/2.0),floor(p.y/16.0),floor(p.z/2.0)))-0.5)*0.07;
 ALBEDO = max(vec3(0.0), c+grain)*day_night_tint.rgb;
}
