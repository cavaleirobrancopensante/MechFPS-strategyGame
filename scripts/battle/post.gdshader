shader_type canvas_item;
// Full-screen finishing pass for the battle view: soft bloom on bright
// things (fire, muzzle flashes, lit windows, the sun), filmic contrast,
// a touch of desaturation, the zone's colour grade, lens vignette, slight
// chromatic fringing at the edges and film grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bloom = 0.6;
uniform float bloom_threshold = 0.72;
uniform vec3 grade = vec3(1.0, 1.0, 1.0);
uniform float saturation = 0.9;
uniform float contrast = 1.08;
uniform float vignette = 0.35;
uniform float grain = 0.035;
uniform float fringe = 0.35;
uniform int taps = 8;

vec3 bright(vec2 uv) {
	vec3 c = textureLod(screen_tex, uv, 2.0).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * clamp((l - bloom_threshold) * 3.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 off = (uv - 0.5);
	float edge = dot(off, off);
	vec3 c;
	c.r = texture(screen_tex, uv + off * px * fringe * 8.0 * edge * 4.0).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - off * px * fringe * 8.0 * edge * 4.0).b;
	if (taps > 0) {
		vec3 b = vec3(0.0);
		float total = 0.0;
		for (int i = 0; i < 12; i++) {
			if (i >= taps) { break; }
			float a = float(i) * 2.399963;
			float r = 6.0 + float(i) * 2.2;
			vec2 o = vec2(cos(a), sin(a)) * r * px * 2.0;
			b += bright(uv + o);
			total += 1.0;
		}
		c += b / max(total, 1.0) * bloom;
	}
	// Filmic-ish curve and grading.
	c = (c - 0.5) * contrast + 0.5;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c *= grade;
	// Vignette.
	c *= 1.0 - vignette * smoothstep(0.1, 0.55, edge * 1.6);
	// Grain.
	float n = fract(sin(dot(uv * vec2(1280.0, 720.0) + TIME * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
