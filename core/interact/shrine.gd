class_name Shrine
extends Interactable
## 雕像（m1-t16，附录 F.2）：战神/精灵/风神/星髓 4 类，各 25 金，每局每类限 1 次。
## 状态接缝：used_kinds 字典由调用方（房间/楼层流）持有并传入 setup —— 同类多座共享 gating。
## 效果落地为本卡约定 meta 接缝（不新增 rig/player 公开字段，消费接线属 T18/集成，已披露）：
## - 战神像 600t 攻速+25%  → atk_speed_boost_until / atk_speed_boost_pct
## - 风神像 300t 移速+30% 且免蓝耗 → move_speed_boost_until / move_speed_boost_pct / energy_free_until
## - 星髓像 3600t 随机元素附魔 → 写 rig.enchant_element（T9 字段），
##   到期恢复所需 prev/until 存 player meta（enchant_element_prev / enchant_element_until）
## - 精灵像 → 召唤 ShieldSpirit 子节点（charges=3，跟随玩家拦截敌方弹）
## wallet 为 duck-typed（同 T14 契约）：spend_coins(n) -> bool；金币不足拒绝且不标记已用。

const PRICE := 25
const KINDS: Array[String] = ["zhanshen", "jingling", "fengshen", "xingsui"]
const KIND_LABELS := {"zhanshen": "战神像", "jingling": "精灵像", "fengshen": "风神像", "xingsui": "星髓像"}
const ATK_BOOST_TICKS := 600        # 10s（60tps）
const ATK_BOOST_PCT := 0.25
const WIND_BOOST_TICKS := 300       # 5s
const WIND_BOOST_PCT := 0.30
const ENCHANT_TICKS := 3600         # 60s
const SPIRIT_CHARGES := 3
const ENCHANTABLE: Array[int] = [Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.POISON, Elements.Id.SHOCK]

var kind := ""
var used_kinds: Dictionary = {}     # 调用方持有的每局状态字典（kind -> true）
var wallet = null                   # duck-typed：spend_coins(n) -> bool
var combat = null                   # 可选 CombatSystem 接缝（精灵像传给 ShieldSpirit）
var rng: RandomNumberGenerator = null   # 星髓像随机附魔用（可注入保测试确定性）

## 装配类别与每局状态；未知 kind 标记无效（can_interact 恒 false，fail-closed）。
func setup(kind_: String, used_kinds_: Dictionary = {}) -> Shrine:
	kind = kind_
	used_kinds = used_kinds_
	if not KINDS.has(kind):
		push_error("Shrine: unknown kind %s" % kind)
		kind = ""
	else:
		action_label = KIND_LABELS[kind]
	return self

func is_used() -> bool:
	return used_kinds.has(kind)

func can_interact(_player: Node2D) -> bool:
	return KINDS.has(kind) and not is_used()

## E 交互入口：默认帧路径（Engine 物理帧）。
func interact(player: Node2D) -> void:
	activate(player as Player, Engine.get_physics_frames())

## 购请落地（frame 显式注入保测试确定性）：门控 → 前置校验 → 扣费 → 标记 → 效果。
func activate(player: Player, frame: int) -> bool:
	if player == null or not can_interact(player):
		return false
	if kind == "xingsui" and (player == null or player.weapon_rig == null):
		push_error("Shrine: xingsui requires weapon_rig")
		return false                      # 前置不满足不消费（不扣费不标记）
	if wallet == null or not wallet.spend_coins(PRICE):
		return false                      # 金币不足拒绝，保持可再试
	used_kinds[kind] = true               # 每局每类限 1 次
	match kind:
		"zhanshen":
			player.set_meta("atk_speed_boost_until", frame + ATK_BOOST_TICKS)
			player.set_meta("atk_speed_boost_pct", ATK_BOOST_PCT)
		"fengshen":
			player.set_meta("move_speed_boost_until", frame + WIND_BOOST_TICKS)
			player.set_meta("move_speed_boost_pct", WIND_BOOST_PCT)
			player.set_meta("energy_free_until", frame + WIND_BOOST_TICKS)
		"xingsui":
			_apply_enchant(player, frame)
		"jingling":
			var spirit := ShieldSpirit.new().setup(player,
				combat if combat != null else player.combat, SPIRIT_CHARGES)
			player.add_child(spirit)      # 子节点跟随：偏移即 24px 接缝
	return true

## 星髓像：随机元素写 rig.enchant_element（T9 字段），
## prev/until 存 player meta —— 到期恢复属集成接线（已披露，本卡只落状态）。
func _apply_enchant(player: Player, frame: int) -> void:
	var rig := player.weapon_rig
	if rng == null:
		rng = RandomNumberGenerator.new()
	var prev := int(rig.enchant_element)
	rig.enchant_element = ENCHANTABLE[rng.randi_range(0, ENCHANTABLE.size() - 1)]
	player.set_meta("enchant_element_prev", prev)
	player.set_meta("enchant_element_until", frame + ENCHANT_TICKS)
