shader_type canvas_item;
// World geometry pass: vertex colour RGB = light, vertex alpha = 1 - fog.
// Lets every wall, floor and roof fade into the zone's haze in one draw.
uniform vec4 fog_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 lit = t.rgb * vcol.rgb;
	COLOR = vec4(mix(lit, fog_color.rgb, 1.0 - vcol.a), t.a);
}
