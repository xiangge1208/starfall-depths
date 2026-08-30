class_name EnemyFactory
extends RefCounted
## M1-T12 敌人构造工厂。
##
## 数据行先经固定 preload 映射选出正确的 EnemyBase 子类，再在该实例上执行 setup()。
## EnemyBase 本体不再运行时 set_script；未知原型/Boss 脚本 fail-closed，避免生成一个只会
## 空转的基类实例并把坏数据伪装成可玩内容。

const BASE_SCRIPT := preload("res://core/enemies/enemy_base.gd")
const BOSS_BASE_SCRIPT := preload("res://core/enemies/boss_base.gd")

const ARCHETYPES := {
	"charger": preload("res://core/enemies/archetypes/charger.gd"),
	"shooter": preload("res://core/enemies/archetypes/shooter.gd"),
	"orbiter": preload("res://core/enemies/archetypes/orbiter.gd"),
	"suicide": preload("res://core/enemies/archetypes/suicide.gd"),
	"dummy": preload("res://core/enemies/archetypes/dummy.gd"),
	"mushroom_spore": preload("res://core/enemies/archetypes/mushroom_spore.gd"),
	# m2-t9：附录 B 原型通用族（B.1 分裂 / B.2 重装·炮台·召唤·弹幕）
	"splitter": preload("res://core/enemies/archetypes/splitter.gd"),
	"heavy": preload("res://core/enemies/archetypes/heavy.gd"),
	"turret": preload("res://core/enemies/archetypes/turret.gd"),
	"summoner": preload("res://core/enemies/archetypes/summoner.gd"),
	"barrage": preload("res://core/enemies/archetypes/barrage.gd"),
	"combo_charger": preload("res://core/enemies/elites/combo_charger.gd"),
	"zibao_wangchong": preload("res://core/enemies/elites/zibao_wangchong.gd"),
	# m2-t9：附录 B.3 小 Boss 池补齐 ×4
	"stone_shield_monk": preload("res://core/enemies/elites/stone_shield_monk.gd"),
	"undead_gunner": preload("res://core/enemies/elites/undead_gunner.gd"),
	"volt_spider": preload("res://core/enemies/elites/volt_spider.gd"),
	"marsh_toad": preload("res://core/enemies/elites/marsh_toad.gd"),
}

## M1 仅交付 A1 Boss；路径键仍与数据行契约一致，但所有值都是编译期 preload。
const BOSS_SCRIPTS := {
	"res://core/enemies/bosses/vine_colossus.gd": preload(
		"res://core/enemies/bosses/vine_colossus.gd"),
}


## 构造并初始化一个尚未入树的敌人，供纯逻辑测试或宿主自行收养。
static func create(r: Dictionary) -> EnemyBase:
	var enemy := _construct(r)
	if enemy == null:
		return null
	enemy.setup(r)
	return enemy


## 生产装配入口：先构造正确子类，设置局部位置并入树，再 setup；这样 setup 读取的
## global_position 已包含父节点变换，brain_pos 与旧生产路径保持一致。
static func spawn(r: Dictionary, parent: Node, local_position: Vector2) -> EnemyBase:
	if parent == null:
		push_error("EnemyFactory: parent is null")
		return null
	var enemy := _construct(r)
	if enemy == null:
		return null
	enemy.position = local_position
	parent.add_child(enemy)
	enemy.setup(r)
	return enemy


static func _construct(r: Dictionary) -> EnemyBase:
	var script := _script_for(r)
	if script == null:
		return null
	var enemy: EnemyBase = script.new() as EnemyBase
	if enemy == null:
		push_error("EnemyFactory: mapped script is not an EnemyBase")
	return enemy


static func _script_for(r: Dictionary) -> Script:
	var boss_path := String(r.get("boss_script", ""))
	if not boss_path.is_empty():
		if not BOSS_SCRIPTS.has(boss_path):
			push_error("EnemyFactory: unknown boss script '%s'" % boss_path)
			return null
		return BOSS_SCRIPTS[boss_path] as Script

	var arch := String(r.get("archetype", ""))
	if arch.is_empty():
		return BASE_SCRIPT
	if arch == "boss":
		return BOSS_BASE_SCRIPT
	if not ARCHETYPES.has(arch):
		push_error("EnemyFactory: unknown archetype '%s'" % arch)
		return null
	return ARCHETYPES[arch] as Script
