shader_type spatial;
// World-space PBR surface for level geometry.
//  * triplanar mapping in world space (no UVs needed, uniform texel density)
//  * anti-tiling: two differently rotated/offset samples blended by a noise mask, so large
//    surfaces don't show an obvious repeating pattern
//  * macro variation: low-frequency brightness/hue changes like real weathering
//  * grime: walls get darker and browner towards the ground, broken up by noise
//  * proper triplanar normal mapping ("whiteout" blend)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float scale = 0.5;            // texture repeats per metre
uniform float rough_mult = 1.0;
uniform float metallic = 0.0;
uniform float normal_strength = 1.0;
uniform float sharpness = 6.0;
uniform bool anti_tiling = true;
uniform float macro_strength = 0.12;
uniform float grime_height = 1.1;     // metres above the base of a wall that get dirty (0 = off)
uniform float grime_strength = 0.38;
uniform vec3 grime_color : source_color = vec3(0.28, 0.24, 0.19);
uniform float base_y = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.13) * 0.3 + vnoise(p * 4.7) * 0.15; }

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

// one planar projection with anti-tiling
vec4 sample_aa(sampler2D t, vec2 uv, float mask) {
	vec4 a = texture(t, uv);
	if (!anti_tiling) return a;
	vec4 b = texture(t, rot(0.63) * uv * 0.87 + vec2(0.31, 0.57));
	return mix(a, b, mask);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(sharpness));
	w /= (w.x + w.y + w.z);
	vec2 uvx = wpos.zy * scale;
	vec2 uvy = wpos.xz * scale;
	vec2 uvz = wpos.xy * scale;
	float mask = smoothstep(0.35, 0.65, fbm(wpos.xz * 0.23 + wpos.y * 0.11));

	vec3 alb = sample_aa(albedo_tex, uvx, mask).rgb * w.x + sample_aa(albedo_tex, uvy, mask).rgb * w.y + sample_aa(albedo_tex, uvz, mask).rgb * w.z;
	float rgh = sample_aa(rough_tex, uvx, mask).r * w.x + sample_aa(rough_tex, uvy, mask).r * w.y + sample_aa(rough_tex, uvz, mask).r * w.z;
	float ao = texture(ao_tex, uvx).r * w.x + texture(ao_tex, uvy).r * w.y + texture(ao_tex, uvz).r * w.z;

	// triplanar normal map (whiteout blend), tangent normals -> world
	vec3 tx = texture(normal_tex, uvx).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_tex, uvy).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_tex, uvz).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength; ty.xy *= normal_strength; tz.xy *= normal_strength;
	vec3 sgn = sign(n);
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// weathering
	float macro = fbm(wpos.xz * 0.045 + vec2(wpos.y * 0.05)) - 0.5;
	alb *= 1.0 + macro * macro_strength * 2.0;
	alb = mix(alb, alb * vec3(1.03, 1.0, 0.95), clamp(macro + 0.5, 0.0, 1.0) * macro_strength);
	if (grime_height > 0.0) {
		float wall = 1.0 - smoothstep(0.35, 0.7, abs(n.y));
		float h = 1.0 - smoothstep(0.0, grime_height, wpos.y - base_y);
		float g = wall * h * (0.55 + 0.45 * fbm(wpos.xz * 1.7 + wpos.y * 3.0)) * grime_strength;
		alb = mix(alb, alb * grime_color * 2.2, g);
		rgh = mix(rgh, 1.0, g * 0.5);
	}
	ALBEDO = alb * tint.rgb;
	ROUGHNESS = clamp(rgh * rough_mult, 0.02, 1.0);
	METALLIC = metallic;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
}
