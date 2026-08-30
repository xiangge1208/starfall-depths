class_name EnemyBase
extends CharacterBody2D
## 敌人状态机（GDD §12.2）：IDLE→ALERT(24t)→ENGAGE；AI 决策在 EnemyBrain（可注入帧测试）。

enum State { IDLE, ALERT, ENGAGE, DEAD }
const ALERT_TICKS := 24     # 0.4s
const VISION_PX := 240.0    # 视距（物理表现层用）

const BERSERK_WINDUP_SCALE := 0.7   # m1-t12 狂暴：50% 血后攻速 ×1.3（设计 §12.3）→ windup ×0.7

var row: Dictionary
var hp := 10
var hp_max := 0                     # m1-t12 虹吸/狂暴基准：_test_init 时取行 hp（坚甲词缀同步 ×3）
var state := State.IDLE
var fired_this_tick := false
var exploded := false
var brain_pos := Vector2.ZERO
var combat: CombatSystem = null    # 房间注入
var combat_bounds := Rect2()       # 房间可玩内域（Boss 安全区/召唤落点约束；空矩形=脑测兜底）
var status: Node = null            # StatusComponent，m0-t11 注入
var player_ref = null              # 玩家替身/实例（需有 brain_pos），房间注入
var stun_until := -1               # m1-t2 坚守眩晕窗：frame < stun_until 时 brain 空转
# ---- m1-t12 精英词缀落点（EliteAffix.apply 写入；默认值即无词缀原行为）----
var split_on_death := false        # 分裂：die() 经 spawn_callback 生成 2 个同 row 子体（hp 半）
var spawn_callback := Callable()   # 房间注入：func(row_id: String, pos: Vector2,
                                   #   row_override: Dictionary = {}) -> Node（分裂路径传净行）
var counts_for_wave := true        # 生产波次体=true；召唤/分裂子体=false，死亡不得消费 RoomFlow
var barrage_extra := 0             # 弹幕大师：shooter 每轮 volley = 1 + barrage_extra
var leech := false                 # 虹吸：接触伤害命中时自回等量 hp（≤ hp_max）
var body_scale := 1.0              # 体型：行 body_scale（小 Boss 1.25）→ 战斗半径与视觉同步放大
var has_berserk := false           # 狂暴门控：仅带词缀者 berserk_active() 才可能为真
var _seen_frame := -1
var _slow_action_credit := 0.0     # 冰缓以 0.7 行动频率推进，不永久改写敌人行数据

func _test_init(r: Dictionary) -> void:
	# 原型选择已由 EnemyFactory 在构造前完成；本方法只初始化当前正确子类实例。
	row = r
	hp = int(r.get("hp", 10))
	hp_max = int(r.get("hp", 10))
	body_scale = float(r.get("body_scale", 1.0))
	brain_pos = Vector2.ZERO
	# 纯脑层测试同样按行建立状态组件；setup() 路径会复用，不重复挂载。
	if status == null:
		var s := StatusComponent.new()
		add_child(s)
		var boss := _row_is_boss(r)
		var elite := not (r.get("elite_affixes", []) as Array).is_empty()
		s.setup(4 if boss or elite else 2, boss)
		status = s
	else:
		var existing := status as StatusComponent
		var boss := _row_is_boss(r)
		var elite := not (r.get("elite_affixes", []) as Array).is_empty()
		existing.setup(4 if boss or elite else 2, boss)

func setup(r: Dictionary) -> void:
	# Factory.spawn 在入树后调用，因此此处读取的是带父节点变换的权威世界位置。
	var at := global_position
	var bs := float(r.get("body_scale", 1.0))
	_test_init(r)
	brain_pos = at
	if bs != 1.0:
		scale = Vector2.ONE * bs   # m1-t12 体型：视觉（含子碰撞形状）同步 ×body_scale
	# _test_init 已按普通/精英/Boss 行配置状态组件。
	# m1-t12：行内精英词缀在装配完成后应用（数值倍率/死亡分裂/吸血/弹幕/狂暴）。
	for affix in r.get("elite_affixes", []):
		EliteAffix.apply(self, String(affix))

func on_player_seen(frame: int) -> void:
	if state == State.IDLE:
		state = State.ALERT
		_seen_frame = frame

func brain_tick(frame: int) -> void:
	fired_this_tick = false
	if frame < stun_until:
		return                       # m1-t2 眩晕：整拍空转（含 ALERT→ENGAGE 推进）
	if status != null:
		if status.is_frozen(frame):
			return
		var speed_mult: float = status.action_speed_multiplier(frame)
		if speed_mult < 1.0:
			_slow_action_credit += speed_mult
			if _slow_action_credit < 1.0:
				return
			_slow_action_credit -= 1.0
		else:
			_slow_action_credit = 0.0
	match state:
		State.ALERT:
			if frame - _seen_frame >= ALERT_TICKS:
				state = State.ENGAGE
				_on_engage_start(frame)   # 转换拍钩子：接触触发型原型（苦力虫引信）在此拍锚定
		State.ENGAGE:
			_engage(frame)
		_:
			pass

func _engage(_frame: int) -> void:
	pass                                  # 原型覆写

## 进入 ENGAGE 的转换拍调用一次（此后每拍走 _engage）；默认无操作，
## 其余原型不覆写即完全保持原行为（不多不少一拍）。
func _on_engage_start(_frame: int) -> void:
	pass

func fire_bullet(target: Vector2, frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var dir := (target - brain_pos).normalized()
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * float(row.get("bullet_speed", 110)),
		"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
		"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
		"radius": float(row.get("bullet_radius", 3.0)),
		"source_type": "projectile", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "弹幕",
	})
	AudioMgr.play("shoot_enemy")         # m2-t5：敌方实际出弹音（combat 未注入的脑层测试不触发）

func take_hit(ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	var frame := int(ctx.get("frame", Engine.get_physics_frames()))
	var hp_before := maxi(hp, 0)
	var amount := int(ctx["amount"])
	if status != null:
		amount = 0 if amount <= 0 else maxi(1, int(floor(float(amount) * status.damage_multiplier(frame))))
	var actual := mini(hp_before, maxi(amount, 0))
	var resolved := ctx.duplicate()
	resolved["amount"] = actual
	hp = hp_before - actual
	EventBus.enemy_damaged.emit(actual, bool(ctx.get("is_crit", false)))   # 实际落地伤害；overkill/负数不虚高
	if _is_player_damage(ctx):
		EventBus.player_damage_resolved.emit(actual, frame)
	Fx.on_enemy_hit(self, resolved)
	if status != null:
		status.apply_hit_context(resolved, actual, frame)
		_consume_status_events(frame)
	if hp <= 0:
		die()

func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_split_spawn_children()   # m1-t12 分裂词缀：先落子体再退场
	var delay := int(row.get("delayed_death_ticks", 0))
	if delay > 0:
		_spawn_delayed_blast(delay)   # m1-t12 自爆王虫：死亡延迟大爆（B.3「本体死亡延迟 1s」）
	else:
		_death_explosion()   # m0-final fix4：死亡即刻爆由 die() 统一持有（附录 B.1「死亡即刻爆」）
	if combat != null:
		combat.unregister_body(self)
	died.emit(self)
	EventBus.enemy_killed.emit(String(row.get("id", "")))
	queue_free()


## 精确实例死亡信号：全局 enemy_killed(id) 为兼容/遥测保留；房间波次必须用本信号，
## 否则同 id 多实例（召唤环/分裂）无法可靠匹配死亡体与 counts_for_wave。
signal died(enemy: EnemyBase)

## m1-t12 分裂词缀执行：经 spawn_callback(row_id, pos, row_override) 生成 2 个同 row 子体
## （hp 为行 hp 一半）。row_override 为行拷贝并剥离 elite_affixes——子体是普通体，
## 不经房间 setup 重挂词缀（防分裂链式继承）。回调未注入（脑层测试/未接线）则跳过。
func _split_spawn_children() -> void:
	if not split_on_death or not spawn_callback.is_valid():
		return
	var child_row: Dictionary = (row as Dictionary).duplicate(true)
	child_row.erase("elite_affixes")
	# 把半血写入构造行，让生产 Factory.setup 同时得到一致的 hp/hp_max，
	# 而不是构造后只改当前 hp（否则子体会以半血/满血上限出生）。
	var half := maxi(int(float(child_row.get("hp", 10)) * 0.5), 1)
	child_row["hp"] = half
	var r := combat_radius()
	for i in 2:
		var child: Node = spawn_callback.call(String(row.get("id", "")),
			brain_pos + Vector2(r if i == 0 else -r, 0.0), child_row)
		if child != null:
			child.set("hp", half)
			if "hp_max" in child:
				child.set("hp_max", half)
			if "split_on_death" in child:
				child.set("split_on_death", false)
			if "counts_for_wave" in child:
				child.set("counts_for_wave", false)

## m1-t12 延迟大爆：生成 DelayedBlast 节点（挂 combat 下，无 combat 且在树内挂场景根；
## 纯脑层测试两者皆无则不生成），到点按 _death_explosion 同语义结算（M0 爆炸语义复用）。
func _spawn_delayed_blast(delay_ticks: int) -> void:
	if int(row.get("aoe_radius", 0)) <= 0 or int(row.get("aoe_dmg", 0)) <= 0:
		return
	var blast := DelayedBlast.new()
	blast.setup({
		"pos": brain_pos, "radius": float(row["aoe_radius"]),
		"dmg": int(row["aoe_dmg"]), "ticks": delay_ticks, "player": player_ref,
		"source_type": "explosion", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "延迟大爆",
	})
	if combat != null:
		combat.add_child(blast)
	elif is_inside_tree():
		get_tree().current_scene.add_child(blast)
	else:
		blast.free()   # 无处挂载（纯脑层测试）：即时释放防泄漏（fix1）

## m0-final fix4：行含 aoe_radius>0 且 aoe_dmg>0 时对范围内玩家结算 aoe_dmg。
## 经 player_ref.take_hit（ctx 带 is_crit=false / element=NONE / from=global_position），
## 玩家受击无敌帧天然节流；M0 无敌方友伤。引信致死与受击致死共用此单一爆炸源。
func _death_explosion() -> void:
	if int(row.get("aoe_radius", 0)) <= 0 or int(row.get("aoe_dmg", 0)) <= 0:
		return
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	if player_ref.brain_pos.distance_to(brain_pos) > float(row["aoe_radius"]):
		return
	player_ref.take_hit({
		"amount": int(row["aoe_dmg"]), "is_crit": false,
		"element": Elements.Id.NONE, "from": global_position,
		"source_type": "explosion", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "自爆",
	})

func combat_radius() -> float:
	return float(row.get("radius", 6.0)) * float(body_scale)

## m1-t12 狂暴：仅带词缀（has_berserk，由 EliteAffix 应用）且血量低于 50%（严格 <）时激活
## ——charger/shooter 蓄力窗 ×0.7（攻速 ×1.3）。普通体不触发（fix1：词缀门控）。
func berserk_active() -> bool:
	return has_berserk and hp * 2 < hp_max

## 蓄力拍数取值：行 windup_ticks（缺省用 default_ticks），狂暴激活时 ×0.7（截断取整）。
## charger/shooter 的 windup 计算统一经此钩子（设计 §12.3「50% 血后攻速 ×1.3」）。
func _windup_ticks(default_ticks: int) -> int:
	var w := int(row.get("windup_ticks", default_ticks))
	if berserk_active():
		w = int(float(w) * BERSERK_WINDUP_SCALE)
	return w

func combat_faction() -> int:
	return Projectile.Faction.ENEMY

## 原型取玩家位置；未注入 player_ref（纯 brain 测试）时退化为自身位置（零向量方向，不移动）。
func _player_pos() -> Vector2:
	return player_ref.brain_pos if player_ref != null else brain_pos

# ---- 物理表现层（手动验证；测试直接驱动 brain，不经此处） ----
func _physics_process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if player_ref != null and state == State.IDLE \
			and global_position.distance_to(player_ref.brain_pos) <= VISION_PX:
		on_player_seen(Engine.get_physics_frames())
	# brain_pos 为权威位置：以差值速度过 move_and_slide 处理碰撞，之后把 brain 对齐实际位置
	velocity = (brain_pos - global_position) * TimeConst.FPS
	move_and_slide()
	brain_pos = global_position
	# m0-t12 fix1：接触伤害（收口 t10 缺口）。玩家侧 0.8s 受击无敌帧天然节流同体连击，不另设冷却；
	# 距离用敌方实际位 vs player_ref.brain_pos（PlayerProxy 每拍镜像）。
	if player_ref != null and int(row.get("contact_dmg", 0)) > 0 \
			and global_position.distance_to(player_ref.brain_pos) <= combat_radius() + 6.0:
		var dealt := int(row["contact_dmg"])
		player_ref.take_hit({
			"amount": dealt, "is_crit": false,
			"element": Elements.Id.NONE, "from": global_position,
			"source_type": "contact", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "接触冲撞",
		})
		# m1-t12 虹吸：接触伤害命中（dealt>0）时自回等量 hp（≤ hp_max；实际节流仍由玩家无敌帧持有）
		if leech and dealt > 0:
			hp = mini(hp + dealt, hp_max)
	# m0-t12 接线：DoT 结算 + 共鸣事件消费（读后清空）
	if status != null:
		var frame := Engine.get_physics_frames()
		var dot: int = status.tick(frame)
		if dot > 0:
			take_hit({
				"amount": dot, "is_crit": false, "element": Elements.Id.NONE,
				"from": global_position, "frame": frame, "source_type": "status",
				"source_id": "element_dot", "source_name": "元素异常", "attack_name": "持续伤害",
				"player_damage": true,
			})
			if state == State.DEAD:
				return
		_consume_status_events(frame)

func _consume_status_events(frame: int) -> void:
	if status == null:
		return
	var effect: Dictionary = status.consume_effect_event()
	if int(effect.get("effect", StatusComponent.Effect.NONE)) == StatusComponent.Effect.SHOCK:
		stun_until = maxi(stun_until, int(effect["until"]))
		_shock_chain()
	if status.resonance_event.is_empty():
		return
	var ev: Dictionary = status.resonance_event
	status.resonance_event = {}
	EventBus.resonance_triggered.emit(int(ev["reaction"]), global_position, ev)
	match int(ev["reaction"]):
		Resonance.R.SHATTER:
			_shatter_aoe(int(ev["last_damage"]))
		Resonance.R.BLAZE:
			if combat != null:
				combat.spawn_blaze_cloud(global_position, frame)
		Resonance.R.SUPERCONDUCT:
			status.apply_superconduct(0.2 if status.is_boss else 0.4, TimeConst.ticks(4.0), frame)
		Resonance.R.ELECTROLYSIS:
			_electrolysis(frame)

func _shock_chain() -> void:
	if combat == null:
		return
	var nearby := combat.bodies_in_radius(global_position, 80.0, Projectile.Faction.ENEMY, self, 1)
	if nearby.is_empty():
		return
	nearby[0].take_hit({
		"amount": 8, "is_crit": false, "element": Elements.Id.NONE, "from": global_position,
		"source_type": "status", "source_id": String(row.get("id", "")),
		"source_name": "麻痹", "attack_name": "跳电",
		"player_damage": true,
	})

func _electrolysis(frame: int) -> void:
	stun_until = maxi(stun_until, frame + TimeConst.ticks(0.8))
	if combat == null:
		return
	for body in combat.bodies_in_radius(global_position, 100.0, Projectile.Faction.ENEMY, self, 3):
		body.set("stun_until", maxi(int(body.get("stun_until")), frame + TimeConst.ticks(0.8)))

## 淬爆（SHATTER）M0 执行：以自身为中心 90px 全向 AoE，对敌方体结算 1.5× 触发伤害。
## m0-final fix3：触发体自身不免（不自践踏），本拍已死者跳过（防同拍重复结算）。
## M0 武器无元素，此通路暂不可达（为 t13+/元素武器预留，行为按控制器决议字面实现）。
func _shatter_aoe(last_damage: int) -> void:
	if combat == null:
		return
	var amount := int(float(last_damage) * 1.5)
	for body in combat.bodies_in_arc(global_position, 0.0, 90.0, 360.0, Projectile.Faction.ENEMY):
		if body == self or body.get("state") == State.DEAD:
			continue
		body.take_hit({"amount": amount, "is_crit": false, "element": Elements.Id.NONE,
			"from": global_position, "source_type": "player_status", "player_damage": true})

func _row_is_boss(r: Dictionary) -> bool:
	return self is BossBase or String(r.get("archetype", "")) == "boss" or String(r.get("boss_script", "")) != "" \
		or r.has("phases")

## 玩家直接武器、反弹弹、元素状态/共鸣都应进入本局 DPS；敌方/环境伤害不进入。
func _is_player_damage(ctx: Dictionary) -> bool:
	if ctx.has("player_damage"):
		return bool(ctx["player_damage"])
	var source_type := String(ctx.get("source_type", ""))
	return source_type == "weapon" or source_type == "melee" or source_type == "player_status"
