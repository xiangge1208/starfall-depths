shader_type canvas_item;
// 命中白闪（m0-t12）：flash_amount 由 Fx 每帧衰减 1→0；
// telegraph（蓄力/引信预警）用 flash_color=红、更慢的衰减。
// 入片元 COLOR 已含 Polygon2D 顶点色与 modulate，只混 RGB、保 alpha。

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, flash_color, flash_amount);
}
