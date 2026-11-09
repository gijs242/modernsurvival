shader_type spatial;
// Woven-fabric camouflage: 3-4 colour blotch pattern driven by object-space noise,
// with a fabric normal map for the weave. Used on soldier uniforms.

uniform vec3 c0 : source_color = vec3(0.45, 0.4, 0.3);
uniform vec3 c1 : source_color = vec3(0.32, 0.28, 0.2);
uniform vec3 c2 : source_color = vec3(0.55, 0.5, 0.4);
uniform vec3 c3 : source_color = vec3(0.22, 0.2, 0.16);
uniform float scale = 5.0;
uniform float wear = 0.15;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_rough : hint_roughness_gray, filter_linear_mipmap, repeat_enable;
uniform float weave_scale = 6.0;

varying vec3 opos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise(p) * 0.6 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.12;
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 p = opos * scale;
	float a = fbm(p);
	float b = fbm(p * 1.3 + 7.1);
	vec3 col = c0;
	col = mix(col, c1, smoothstep(0.52, 0.56, a));
	col = mix(col, c2, smoothstep(0.58, 0.62, b) * (1.0 - smoothstep(0.52, 0.56, a)));
	col = mix(col, c3, smoothstep(0.66, 0.7, a));
	// dirt / wear towards the bottom of each part
	float dirt = fbm(p * 3.0) * wear;
	col *= 1.0 - dirt;
	ALBEDO = col;
	NORMAL_MAP = texture(fabric_normal, UV * weave_scale).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.85 + texture(fabric_rough, UV * weave_scale).r * 0.15;
	SPECULAR = 0.3;
}
