shader_type canvas_item;
// "ReShade"-style finishing pass over the 3D view (drawn under the HUD):
//  * contrast-adaptive sharpening (AMD CAS-style) to bring back texture detail after TAA / upscaling
//  * a little vibrance and a lift/gain colour grade (warm highlights, cool shadows)
//  * subtle lens effects: chromatic aberration towards the corners, vignette, fine film grain

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float sharpen : hint_range(0.0, 1.0) = 0.55;
uniform float vibrance = 0.14;
uniform vec3 lift = vec3(0.0, 0.004, 0.018);
uniform vec3 gain = vec3(1.03, 1.0, 0.96);
uniform float vignette = 0.32;
uniform float aberration = 0.0018;
uniform float grain = 0.022;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 dc = uv - 0.5;
	float r2 = dot(dc, dc);
	vec2 ca = dc * aberration * r2 * 4.0;
	vec3 c = vec3(texture(screen, uv + ca).r, texture(screen, uv).g, texture(screen, uv - ca).b);
	vec3 n = texture(screen, uv + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen, uv + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen, uv + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen, uv + vec2(-px.x, 0.0)).rgb;
	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 wgt = amp * (-1.0 / mix(8.0, 5.0, sharpen));
	c = clamp((c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt), 0.0, 1.0);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	c = mix(vec3(l), c, 1.0 + vibrance * (1.0 - sat));
	c = c * gain + lift * (1.0 - c);
	c *= 1.0 - vignette * smoothstep(0.08, 0.5, r2);
	c += (hash(uv * 1000.0 + fract(TIME * 7.13)) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
