class_name TestVisualEnhancements
extends GdUnitTestSuite

## 视觉效果与打击感增强测试（对标《元气骑士》）：
## 1. 武器手持外观、360°旋转瞄准、左右翻转、开火后坐力、近战刀光弧
## 2. 实体脚下椭圆阴影 DropShadow
## 3. 子弹飞行朝向旋转 rotation = vel.angle()
## 4. PostProcess 后处理管线（WorldEnvironment Bloom 与暗角）

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const DROP_SHADOW_SCRIPT := preload("res://fx/drop_shadow.gd")
const WEAPON_VISUAL_SCRIPT := preload("res://core/player/weapon_visual.gd")
const POST_PROCESS_SCRIPT := preload("res://fx/post_process.gd")

func test_player_scene_contains_weapon_visual_and_drop_shadow() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	assert_object(p).is_not_null()
	assert_object(p.get_node_or_null("DropShadow")).is_not_null()
	assert_object(p.get_node_or_null("WeaponVisual")).is_not_null()

func test_weapon_visual_aim_and_flip() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var wv = p.get_node("WeaponVisual")
	assert_object(wv).is_not_null()

	# 朝右瞄准：旋转约为 0，flip_v 为 false
	p.facing = Vector2.RIGHT
	wv.call("_update_aim_and_depth")
	assert_float(wv.pivot.rotation).is_between(-0.01, 0.01)
	assert_bool(wv.main_sprite.flip_v).is_false()

	# 朝左瞄准：旋转约为 PI，flip_v 为 true（防止武器倒立）
	p.facing = Vector2.LEFT
	wv.call("_update_aim_and_depth")
	assert_bool(wv.main_sprite.flip_v).is_true()

	# 朝上瞄准：z_index 为 -1（在身体后面）
	p.facing = Vector2.UP
	wv.call("_update_aim_and_depth")
	assert_int(wv.main_sprite.z_index).is_equal(-1)

	# 朝下瞄准：z_index 为 1（在身体前面）
	p.facing = Vector2.DOWN
	wv.call("_update_aim_and_depth")
	assert_int(wv.main_sprite.z_index).is_equal(1)

func test_weapon_visual_updates_texture_on_equip() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var wv = p.get_node("WeaponVisual")
	var rig: WeaponRig = p.get_node("WeaponRig") as WeaponRig

	rig.equip("laohuoji")
	assert_bool(wv.main_sprite.visible).is_true()
	assert_object(wv.main_sprite.texture).is_not_null()

func test_weapon_visual_recoil_on_fire() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var wv = p.get_node("WeaponVisual")
	wv.call("_on_weapon_fired", {}, Vector2.RIGHT, false)
	# 开火瞬间后坐力后退 2.5px
	assert_float(wv.main_sprite.position.x).is_equal(2.5)

func test_weapon_visual_melee_swing_and_slash_arc() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var wv = p.get_node("WeaponVisual")
	wv.call("_on_melee_swung", {"range": 48.0, "arc_deg": 100.0}, Vector2.RIGHT)
	assert_bool(wv.slash_sprite.visible).is_true()
	assert_float(wv.slash_sprite.scale.x).is_greater(1.0)

func test_drop_shadow_component() -> void:
	var shadow: Node2D = auto_free(DROP_SHADOW_SCRIPT.new())
	shadow.call("set_shadow_size", 8.0, 4.0, 5.0)
	assert_float(shadow.get("radius_x")).is_equal(8.0)
	assert_float(shadow.get("radius_y")).is_equal(4.0)
	assert_float(shadow.position.y).is_equal(5.0)
	assert_int(shadow.z_index).is_equal(-1)

func test_dress_enemy_sprite_adds_drop_shadow() -> void:
	var host: Node2D = auto_free(Node2D.new())
	var res := ArtLookup.dress_enemy_sprite(host, {"id": "kuli_bug", "radius": 7.0})
	assert_bool(res).is_true()
	assert_object(host.get_node_or_null("DropShadow")).is_not_null()
	assert_object(host.get_node_or_null("Sprite")).is_not_null()

func test_post_process_setup() -> void:
	var scene: Node2D = auto_free(Node2D.new())
	add_child(scene)
	var pp = POST_PROCESS_SCRIPT.apply_to_scene(scene)
	assert_object(pp).is_not_null()
	assert_object(pp.world_env).is_not_null()
	assert_bool(pp.world_env.environment.glow_enabled).is_true()
	assert_object(pp.vignette_layer).is_not_null()

func test_post_process_bullet_hdr_modulate() -> void:
	var base := Color(1.0, 0.5, 0.2, 1.0)
	var normal_col = POST_PROCESS_SCRIPT.get_bullet_hdr_modulate(base, false, false)
	var elem_col = POST_PROCESS_SCRIPT.get_bullet_hdr_modulate(base, false, true)
	var crit_col = POST_PROCESS_SCRIPT.get_bullet_hdr_modulate(base, true, false)

	# 普通弹 > 1.0 (触发 Bloom 辉光)
	assert_float(normal_col.r).is_greater(1.0)
	# 元素弹比普通弹更亮
	assert_float(elem_col.r).is_greater(normal_col.r)
	# 暴击弹最亮 (1.6x)
	assert_float(crit_col.r).is_greater(elem_col.r)
	# Alpha 保持不变
	assert_float(normal_col.a).is_equal(1.0)
