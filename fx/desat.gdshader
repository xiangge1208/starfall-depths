shader_type canvas_item;
// 玩家死亡去饱和（M3 Juice v2 §2 J1「0.3× 慢速 600ms + 去饱和渐入 0.4s → 死亡结算」，
// D-3a 补课）：全屏 hint_screen_texture 采样 + 亮度加权去饱和，progress 由 Fx 按真实
// 毫秒推进（慢速段 time_scale 0.3 不拉长渐入）。无缩放/无重采样/无过滤切换
// （480×270 像素风红线；采样与屏同分辨率，最近邻语义保持）。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(col, vec3(luma), progress), 1.0);
}
