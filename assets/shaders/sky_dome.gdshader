shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

// 天空穹顶渐变：从天顶的深蓝过渡到地平线的浅蓝白。
// 模型本身没有贴图，这里用紫外线的高度比例做渐变，再接一点太阳方向的高光。

uniform vec3 zenith_color : source_color = vec3(0.10, 0.34, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.79, 0.96);
uniform vec3 ground_color : source_color = vec3(0.45, 0.52, 0.55);
uniform float height_scale = 18.0;
uniform float sun_strength = 0.35;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);

void fragment() {
	// VERTEX 是模型本地坐标，穹顶本地高度大约 0~18
	float h = clamp(VERTEX.y / height_scale, 0.0, 1.0);
	vec3 sky = mix(horizon_color, zenith_color, pow(h, 0.75));

	// 地平线以下稍微压暗，避免底部穿帮
	float below = smoothstep(0.08, -0.02, VERTEX.y / height_scale);
	sky = mix(sky, ground_color, below);

	// 太阳方向的一圈亮部
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sun = max(dot(world_normal, normalize(sun_direction)), 0.0);
	sky += vec3(1.0, 0.92, 0.72) * pow(sun, 6.0) * sun_strength;

	ALBEDO = sky;
}
