class_name ArtLookup
extends RefCounted
## m1-t28 生成像素占位美术接线查询（纯静态、可单测）：data id → art/generated 纹理路径。
##
## 契约（art/generated/MANIFEST.md 接线表）：
## - 所有表驱动路径必须真实存在（test_art_lookup 逐项断言）；查不到返回 ""，
##   调用方回落原色块表现并 push_warning 留痕 —— 绝不给 load() 塞坏路径。
## - 所有 Sprite2D 统一最近邻过滤（像素风必需）。
## - 受击白闪（Fx._find_sprite）按节点名 "Sprite" 寻址：游戏体挂的 Sprite2D 一律保留该名。

const BASE := "res://art/generated/"

## 六英雄站立像（data/heroes.json id → characters/hero_<id>.png）。
const HERO_TEXTURES := {
	"vanguard": "characters/hero_vanguard.png",
	"ranger": "characters/hero_ranger.png",
	"assassin": "characters/hero_assassin.png",
	"engineer": "characters/hero_engineer.png",
	"guardian": "characters/hero_guardian.png",
	"mage": "characters/hero_mage.png",
}

## 敌人名录 → enemies/<id>.png（name == data id；M1 八行全量 + M2 附录 B/C 预置行）。
const ENEMY_TEXTURES := {
	"kuli_bug": "enemies/kuli_bug.png",
	"cave_bat": "enemies/cave_bat.png",
	"crossbowman": "enemies/crossbowman.png",
	"vine_charger": "enemies/vine_charger.png",
	"mushroom_spore": "enemies/mushroom_spore.png",
	"shuangdao_lizardman": "enemies/shuangdao_lizardman.png",
	"zibao_wangchong": "enemies/zibao_wangchong.png",
	"vine_colossus": "enemies/vine_colossus.png",
	"vine_charger_elite": "enemies/vine_charger_elite.png",
	"vine_charger_miniboss": "enemies/vine_charger_miniboss.png",
	"mud_slime": "enemies/mud_slime.png",
	"hardshell_turtle": "enemies/hardshell_turtle.png",
	"wing_lizard": "enemies/wing_lizard.png",
	"thorn_turret": "enemies/thorn_turret.png",
	"spore_flower": "enemies/spore_flower.png",
	"stone_boar": "enemies/stone_boar.png",
	"ruin_archer": "enemies/ruin_archer.png",
	"moss_slime": "enemies/moss_slime.png",
	"glowbug_swarm": "enemies/glowbug_swarm.png",
	"old_tree_guard": "enemies/old_tree_guard.png",
	"seed_pitcher": "enemies/seed_pitcher.png",
	"crystal_bat": "enemies/crystal_bat.png",
	"ice_mage": "enemies/ice_mage.png",
	"magnet_golem": "enemies/magnet_golem.png",
	"ghost_jelly": "enemies/ghost_jelly.png",
	"frost_crab": "enemies/frost_crab.png",
	"crystal_rat": "enemies/crystal_rat.png",
	"rock_crystal_turret": "enemies/rock_crystal_turret.png",
	"crystal_summoner": "enemies/crystal_summoner.png",
	"prism_ranger": "enemies/prism_ranger.png",
	"ice_spider": "enemies/ice_spider.png",
	"echo_lurker": "enemies/echo_lurker.png",
	"crystal_dragon": "enemies/crystal_dragon.png",
	"lava_hound": "enemies/lava_hound.png",
	"ash_shooter": "enemies/ash_shooter.png",
	"firerain_priest": "enemies/firerain_priest.png",
	"magma_slime": "enemies/magma_slime.png",
	"obsidian_guard": "enemies/obsidian_guard.png",
	"sulfur_moth": "enemies/sulfur_moth.png",
	"lava_turret": "enemies/lava_turret.png",
	"ember_summoner": "enemies/ember_summoner.png",
	"scorch_stomper": "enemies/scorch_stomper.png",
	"flame_lich": "enemies/flame_lich.png",
	"magma_wyvern": "enemies/magma_wyvern.png",
	"starmarrow_blob": "enemies/starmarrow_blob.png",
	"undead_gunner": "enemies/undead_gunner.png",
	"stone_shield_monk": "enemies/stone_shield_monk.png",
	"volt_spider": "enemies/volt_spider.png",
	"marsh_toad": "enemies/marsh_toad.png",
	"gem_queen": "enemies/gem_queen.png",
	"crystal_golem": "enemies/crystal_golem.png",
	"frost_spider_mother": "enemies/frost_spider_mother.png",
	"magma_tyrant": "enemies/magma_tyrant.png",
	"starfall_prophet": "enemies/starfall_prophet.png",
}

## T12 占位嘉宾（波次标记 id ≠ 数据行 id）按 guest_kind 回落变体图；
## 真实行 id（上表）优先于本表 —— 见 sprite_for_enemy。
const GUEST_FALLBACK := {
	"elite": "enemies/vine_charger_elite.png",
	"miniboss": "enemies/vine_charger_miniboss.png",
	"boss": "enemies/vine_colossus.png",
}

const BULLET_PLAYER := "projectiles/bullet_player.png"
const BULLET_ENEMY := "projectiles/bullet_enemy.png"
## 元素弹（Elements.NAMES → projectiles/elem_<name>.png；NONE 走阵营底图）。
const PICKUP_TEXTURES := {
	"coin": "pickups/coin.png",
	"energy": "pickups/energy.png",
	"heart": "pickups/heart.png",
	"weapon_crate": "pickups/weapon_crate.png",
}

## 地块/门/陈设（16x16 无缝可平铺；按房间生物群系选 floor_*/wall_*）。
## m2-t27（I-3 A2/A3 接线验证）：补 crystal/magma 套件行（T28 生成器已产出图，
## 映射表此前的缺口）——层套件经 biome_set(floor_idx) 寻址；走廊变体随套件可寻址。
const TILES := {
	"floor_cave": "tiles/floor_cave.png",
	"floor_garden": "tiles/floor_garden.png",
	"floor_boss": "tiles/floor_boss.png",
	"floor_crystal": "tiles/floor_crystal.png",
	"floor_magma": "tiles/floor_magma.png",
	"wall_cave": "tiles/wall_cave.png",
	"wall_garden": "tiles/wall_garden.png",
	"wall_boss": "tiles/wall_boss.png",
	"wall_crystal": "tiles/wall_crystal.png",
	"wall_magma": "tiles/wall_magma.png",
	"corridor_floor": "tiles/corridor_floor.png",
	"corridor_crystal": "tiles/corridor_crystal.png",
	"corridor_magma": "tiles/corridor_magma.png",
	"door_closed": "tiles/door_closed.png",
	"door_locked": "tiles/door_locked.png",
	"chest_closed": "tiles/chest_closed.png",
	"prop_pillar": "tiles/prop_pillar.png",
	"prop_crate": "tiles/prop_crate.png",
	"prop_bush": "tiles/prop_bush.png",
	"hazard_vine": "tiles/hazard_vine.png",
	"hazard_lava": "tiles/hazard_lava.png",
}

static var _cache: Dictionary = {}

## 弹丸贴图备忘缓存（M2-T1）：键 = faction<<16 | element（int 复合键零分配）。
## _path_cache_size 为累计 miss 计数（= 已缓存键数），热路径分配探针：
## 测试断言同参二次调用命中缓存（计数不变）。
static var _proj_tex: Dictionary = {}
static var _path_cache_size: int = 0

# ---- 路径查询（纯函数，单测覆盖） ----

static func hero_texture_path(hero_id: String) -> String:
	if HERO_TEXTURES.has(hero_id):
		return BASE + String(HERO_TEXTURES[hero_id])
	return ""

static func enemy_texture_path(enemy_id: String) -> String:
	if ENEMY_TEXTURES.has(enemy_id):
		return BASE + String(ENEMY_TEXTURES[enemy_id])
	return ""

## 敌人外观路径：行 id 精确命中优先，占位嘉宾（id=波次标记）按 guest_kind 回落；
## 未知 id 返回 ""（调用方保留色块 + push_warning）。
static func sprite_for_enemy(row: Dictionary) -> String:
	var by_id := enemy_texture_path(String(row.get("id", "")))
	if not by_id.is_empty():
		return by_id
	var kind := String(row.get("guest_kind", ""))
	if GUEST_FALLBACK.has(kind):
		return BASE + String(GUEST_FALLBACK[kind])
	return ""

## 弹丸路径（m2-t27 元素弹阵营分化）：元素弹（cfg element != NONE）玩家用
## elem_<name>.png，敌方用 elem_<name>_enemy.png（暗边框变体，生成器 variant="enemy"）；
## 无元素保持阵营底图。laser 谱系 M1 无弹形表现（projectiles/laser_seg.png 预留，暂不接线）。
static func projectile_texture_path(is_player: bool, element: int) -> String:
	if element != Elements.Id.NONE:
		var name := String(Elements.NAMES.get(element, ""))
		if not name.is_empty() and name != "none":
			if is_player:
				return BASE + "projectiles/elem_%s.png" % name
			return BASE + "projectiles/elem_%s_enemy.png" % name
	return BASE + (BULLET_PLAYER if is_player else BULLET_ENEMY)

static func pickup_texture_path(kind: String) -> String:
	if PICKUP_TEXTURES.has(kind):
		return BASE + String(PICKUP_TEXTURES[kind])
	return ""

static func tile_path(tile_name: String) -> String:
	if TILES.has(tile_name):
		return BASE + String(TILES[tile_name])
	return ""

## 层生物群系套件（m2-t27 I-3 A2/A3 瓦片接线验证）：floor_idx 1→cave/garden 套、
## 2→crystal 套、3→magma 套。返回 {floor, wall, door} 三键全路径（门各层共用
## door_closed——生成器无 per-biome 门图）；套件走廊变体 corridor_*/crystal/magma
## 经 TILES 寻址。未知层（<1 或 >3）返回空表，由调用方回落。
## floor 1 主体取 cave（普通房）；start 庭院 garden 特例仍由 floor_scene 按房型选。
static func biome_set(floor_idx: int) -> Dictionary:
	var kit := ""
	match floor_idx:
		1:
			kit = "cave"
		2:
			kit = "crystal"
		3:
			kit = "magma"
		_:
			return {}
	return {
		"floor": tile_path("floor_%s" % kit),
		"wall": tile_path("wall_%s" % kit),
		"door": tile_path("door_closed"),
	}

## 武器图标（ui/weapons/<id>.png，115 张全名录按 id 约定寻址）。
static func weapon_icon_path(weapon_id: String) -> String:
	if weapon_id.is_empty():
		return ""
	return BASE + "ui/weapons/%s.png" % weapon_id

# ---- 节点工厂（全部最近邻过滤；坏路径返回 null 由调用方回落） ----

static func tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _cache.has(path):
		var res: Variant = load(path)
		if res == null:
			push_warning("ArtLookup: texture missing '%s'" % path)
			_cache[path] = null
			return null
		_cache[path] = res
	return _cache[path] as Texture2D

## 弹丸贴图热路径查询（M2-T1）：floor_scene/room_combat _sync_bullet_visuals
## 逐帧逐弹调用——静态字典备忘（int 复合键零分配），命中即零字符串拼装/零 load。
static func bullet_texture(faction: int, element: int) -> Texture2D:
	var key := (faction << 16) | (element & 0xFFFF)
	if _proj_tex.has(key):
		return _proj_tex[key] as Texture2D
	_path_cache_size += 1
	var t := tex(projectile_texture_path(faction == Projectile.Faction.PLAYER, element))
	_proj_tex[key] = t
	return t

static func make_sprite(path: String) -> Sprite2D:
	var t := tex(path)
	if t == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = t
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr

## 矩形平铺（地板/墙/走廊）：region + repeat 无缝 16x16（visual 判定留截图证据）。
## rect 为目标覆盖区（父节点坐标系，左上角定位）。
static func make_tiled(path: String, rect: Rect2) -> Sprite2D:
	var spr := make_sprite(path)
	if spr == null:
		return null
	spr.centered = false
	spr.position = rect.position
	spr.region_enabled = true
	spr.region_rect = Rect2(Vector2.ZERO, rect.size)
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return spr

## 玩家外观：读 HeroApplier meta 接缝 "hero"（m1-t11 落行），无 meta 缺省 vanguard
## （训练房/裸玩家路径）。16x16 占位 ×0.75 ≈ 原 12x14 色块 footprint（碰撞形状不动）。
static func apply_player_sprite(player: Node2D) -> void:
	var spr := player.get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	var hero_id := "vanguard"
	if player.has_meta("hero"):
		hero_id = String((player.get_meta("hero") as Dictionary).get("id", hero_id))
	var path := hero_texture_path(hero_id)
	if path.is_empty():
		push_warning("ArtLookup: no hero sprite for '%s'" % hero_id)
		return
	var t := tex(path)
	if t == null:
		return
	spr.texture = t
	spr.hframes = 1                    # m2-t21（T17 Minor①）：写回站立像须清帧表切片，防 4x4 残留裁切
	spr.vframes = 1
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(0.75, 0.75)

## 敌人外观通用装配：按行取图，把纹理按行 radius 装进 ~2r 见方（Boss body_scale 由
## EnemyBase.setup 整节点 ×1.25，视觉随之放大，无需在此处理）。缺图返回 false，
## 调用方保留原色块表现。
static func dress_enemy_sprite(e: Node2D, row: Dictionary) -> bool:
	var path := sprite_for_enemy(row)
	var spr := make_sprite(path)
	if spr == null:
		return false
	spr.name = "Sprite"                        # Fx 白闪按名寻址
	var radius := maxf(float(row.get("radius", 6.0)), 5.0)
	var tsize := spr.texture.get_size()
	var s := (radius * 2.0) / maxf(tsize.x, tsize.y)
	spr.scale = Vector2(s, s)
	e.add_child(spr)
	return true
