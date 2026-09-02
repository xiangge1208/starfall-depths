class_name EnemyBase
extends CharacterBody2D
## 敌人状态机（GDD §12.2）：IDLE→ALERT(24t)→ENGAGE；AI 决策在 EnemyBrain（可注入帧测试）。

enum State { IDLE, ALERT, ENGAGE, DEAD }
const ALERT_TICKS := 24     # 0.4s
const VISION_PX := 240.0    # 视距（物理表现层用）

const BERSERK_WINDUP_SCALE := 0.7   # m1-t12 狂暴：50% 血后攻速 ×1.3（设计 §12.3）→ windup ×0.7

# ---- m4-c3 视界系展示键（表现判定分离，零判定影响；元素视界/共鸣视界） ----
const VISION_MARK_TICKS := 21       # 元素视界：预警进入拍高亮描边淡出窗（0.35s，§7.5 预警下限同源）
const STATUS_OUTLINE_COLORS := {    # 异常状态描边色（GDD §5.1：红火/青冰/绿毒/紫电）
	Elements.Id.FIRE: Color(1.0, 0.35, 0.25, 0.9),
	Elements.Id.ICE: Color(0.4, 0.9, 1.0, 0.9),
	Elements.Id.POISON: Color(0.45, 0.95, 0.4, 0.9),
	Elements.Id.SHOCK: Color(0.75, 0.5, 1.0, 0.9),
}
const VISION_MARK_COLOR := Color(1.0, 0.92, 0.55, 0.95)   # 元素视界预警高亮（亮黄，区别于红闪）

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
var _nan_reset_done := false       # fix1：非有限坐标重置只告警/留痕一次（防警告洪水重现）
# m4-c3 视界系展示层状态（_draw/queue_redraw 专用，判定不读）
var _vision_mark_until := -1       # 元素视界：预警高亮窗终帧（telegraph_fx 写入）
var _status_outline := false       # 共鸣视界：异常状态描边当前态（变化拍 queue_redraw）
var _status_outline_element := -1  # 当前描边元素（取色用；active 首个激活态）

## fix1（m3-b1 报告 69/100 停滞的下游症状防御）：brain_pos 是权威位置，一旦非有限
## （NaN/inf）即经表现层 `velocity = (brain_pos - global_position) * FPS` 传播到
## global_position，再经拍末 `brain_pos = global_position` 回写永久污染——敌人成为
## 「冻结的不可伤幽灵」，房间永不可清，且引擎 normalize 每帧告警（B-1 实测 20min
## 259 万行可拖垮进程）。本守卫在每物理帧表现层入口跑（房间 brain_tick 之后同拍）：
## 检测 → 重置到 combat_bounds 内域中心（生产路径必注入；脑测空 bounds 回原点）
## → push_warning + Telemetry 各留痕一次。返回 false 时本拍跳过表现层，NaN 不跨拍存活。
func ensure_finite_position() -> bool:
	if brain_pos.is_finite() and global_position.is_finite():
		return true
	var target := Vector2.ZERO
	if combat_bounds.size != Vector2.ZERO:
		target = combat_bounds.get_center()
	if not brain_pos.is_finite():
		brain_pos = target
	if not global_position.is_finite():
		global_position = target
	velocity = Vector2.ZERO
	if not _nan_reset_done:
		_nan_reset_done = true
		push_warning("EnemyBase: non-finite position detected and reset to %s (id=%s, bounds=%s)"
				% [target, String(row.get("id", "?")), combat_bounds])
		Telemetry.log_row(["enemy_nan_reset", Engine.get_physics_frames(), String(row.get("id", ""))])
	return false

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
	# m4-c1 电弧链（幽光水母「电弧链射击」，volt_spider SHOCK 电弧弹同款元素归因）：
	# 行 bullet_element 命名元素 → 元素弹；无键/none = NONE（既有弹不受影响）。
	var element := Elements.from_name(String(row.get("bullet_element", "")))
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * enemy_bullet_speed(110),
		"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
		"element": element, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
		"radius": float(row.get("bullet_radius", 3.0)),
		"source_type": "projectile", "source_id": String(row.get("id", "")),
		"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "弹幕",
	})
	if element != Elements.Id.NONE:
		Telemetry.log_row(["enemy_chain_zap", frame, Elements.NAMES[element]],
			String(row.get("id", "")))   # 仅带键敌型上报（现=幽光水母电弧链）
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
	AudioMgr.play("death")   # m2-t5 评审 Major①：所有敌型（含 Boss/分裂体）唯一死亡路径，状态门保证每敌一次
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
## m3-fix1 试炼 enemy_attack_speed_pct 消费端（半边）：蓄力拍 ÷攻速倍率（÷1.0 恒等）。
## m4-c3 元素视界（telegraph_bonus_ticks，player meta）：预警（windup）窗绝对 +flat ticks
## （试炼/狂暴缩放后加算，desc「弹幕/激光预警 +0.15s」= +9t；冷却节奏
## _attack_cooldown_ticks 不受影响——只延预警窗）。无增益 meta 缺省 0 恒等。
func _windup_ticks(default_ticks: int) -> int:
	var w := int(row.get("windup_ticks", default_ticks))
	if berserk_active():
		w = int(float(w) * BERSERK_WINDUP_SCALE)
	return _scaled_attack_ticks(w) + _player_buff_meta("buff_telegraph_bonus_ticks")

## m3-fix1 试炼 enemy_attack_speed_pct 消费端：攻击节奏拍数 ÷攻速倍率
## （攻速 ×1.2 ⇔ 拍数 ÷1.2；≤0 原样（0 拍语义保持）；÷1.0 为精确恒等零漂移）。
func _scaled_attack_ticks(ticks: int) -> int:
	if ticks <= 0:
		return ticks
	return maxi(int(round(float(ticks) / TrialMods.enemy_attack_speed_scale())), 1)

## 攻击冷却拍数统一取值（m3-fix1 收敛 6 处 `maxi(cd - windup, 0)` 字面重复）：
## 行 cd_ticks − 行 windup_ticks（同键缺省语义不变），再经 _scaled_attack_ticks
## 应用试炼攻速倍率。狂暴只作用于 windup（既有语义不变）。
func _attack_cooldown_ticks(default_cd: int, default_windup := 30) -> int:
	var base := maxi(int(row.get("cd_ticks", default_cd)) - int(row.get("windup_ticks", default_windup)), 0)
	return _scaled_attack_ticks(base)

## m3-fix1 试炼 bullet_speed_pct 消费端：敌方出弹速度统一经此读行键
## （慢弹等比提速、快弹封顶 150px/s；无因子恒等，见 TrialMods.enemy_bullet_speed_px）。
func enemy_bullet_speed(default_px: float) -> float:
	return TrialMods.enemy_bullet_speed_px(float(row.get("bullet_speed", default_px)))

func combat_faction() -> int:
	return Projectile.Faction.ENEMY


# ---- m4-c3 视界系展示键（element_vision / telegraph_bonus_ticks / resonance_vision） ----

## 玩家 buff meta 读缝（player_ref 两态：PlayerProxy 镜像替身 / 直注入 Player；测试
## 替身无 player/无 meta → 0）。仅预警/描边低频路径调用，非每帧热路径。
func _player_buff_meta(key: String) -> int:
	var p: Node = null
	if player_ref is PlayerProxy:
		p = player_ref.player
	elif player_ref is Player:
		p = player_ref
	if p == null:
		return 0
	return int(p.get_meta(key, 0))

## 预警（蓄力/引信/前摇）进入拍统一出口：既有红闪 Fx telegraph 通道原样保留；
## 玩家持有元素视界（buff_element_vision flag）时叠敌侧自绘高亮描边（更醒目，
## VISION_MARK_TICKS 淡出窗，纯表现零判定影响）。19 处原型/精英/Boss 预警纹路径
## 统一改呼本口（行为等价替换）。
func telegraph_fx() -> void:
	Fx.on_enemy_hit(self, {"telegraph": true})
	if _vision_mark_until < 0 and _player_buff_meta("buff_element_vision") > 0:
		_vision_mark_until = Engine.get_physics_frames() + VISION_MARK_TICKS
		queue_redraw()

## 视界系描边每拍维护（_physics_process 拍内调用；纯逻辑可无头直测）：
## ①预警高亮窗过期清位；②共鸣视界（buff_resonance_vision flag）——目标处于异常
## 状态（StatusComponent.active 非空）时描边，状态集变化拍 queue_redraw（恒等帧零重绘）。
func update_vision_outlines(frame: int) -> void:
	if _vision_mark_until > 0 and frame >= _vision_mark_until:
		_vision_mark_until = -1
		queue_redraw()
	var outlined := false
	var element := -1
	if status is StatusComponent and not (status as StatusComponent).active.is_empty() \
			and _player_buff_meta("buff_resonance_vision") > 0:
		outlined = true
		for e: int in (status as StatusComponent).active:
			element = e
			break                       # 确定性取首个激活元素（ELEMENT_ORDER 内层序）
	if outlined != _status_outline or (outlined and element != _status_outline_element):
		_status_outline = outlined
		_status_outline_element = element
		queue_redraw()

func _draw() -> void:
	# 表现层自绘（脑层测试无树不触发；draw 预算：描边仅在有增益时存在，同屏 ≤ 敌数）
	var r := combat_radius() + 2.0
	if Engine.get_physics_frames() < _vision_mark_until:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, VISION_MARK_COLOR, 1.5)
	if _status_outline:
		var col: Color = STATUS_OUTLINE_COLORS.get(_status_outline_element,
			Color(0.9, 0.9, 0.9, 0.9))
		draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 20, col, 1.5)


## m4-c1 接触伤害元素归因钩子（缺省 NONE 不变）：熔岩犬「两段扑咬，附带燃烧」覆写为
## FIRE（扑咬=冲刺接触伤，燃烧=火元素归因；玩家侧无敌帧节流语义不变）。
func _contact_element() -> int:
	return Elements.Id.NONE


## m4-c1 玩家武器行读缝（模仿武器用；经 PlayerProxy.current_weapon_row 只读 GameDB）。
## player_ref 无该接缝（测试 SpyPlayer 等）返回 {}，调用方回退默认行为。
func _player_weapon_row() -> Dictionary:
	if player_ref == null or not player_ref.has_method("current_weapon_row"):
		return {}
	return player_ref.call("current_weapon_row")


## m4-c1 派味特技蓄力拍（专用键优先）：行 pull_/claw_windup_ticks 专用键 > 既有
## windup_ticks > default_ticks。注意 GameDB.ENEMY_OPTIONAL 对未填的 windup_ticks
## 预填 0，`row.get("windup_ticks", d)` 的缺省永不被用到——故 0 值一律按缺省回落
## （防特技 windup 被预填零击穿）。狂暴 ×0.7 / 试炼攻速缩放与 _windup_ticks 同口径。
func _signature_windup(specific_key: String, default_ticks: int) -> int:
	var w := int(row.get(specific_key, 0))
	if w <= 0:
		w = int(row.get("windup_ticks", default_ticks))
	if w <= 0:
		w = default_ticks
	if berserk_active():
		w = int(float(w) * BERSERK_WINDUP_SCALE)
	return _scaled_attack_ticks(w)


## m4-c1 派味特技冷却拍（专用 cd 键优先）：专用键口径 = 全周期（含专用 windup），
## cool = 专用 cd − 专用 windup；无专用键回落 _attack_cooldown_ticks 既有语义
## （该路径行必须自带 cd_ticks，否则预填 0 同样击穿——两行特技键齐备，不触此路）。
func _signature_cooldown(specific_cd_key: String, specific_windup_key: String,
		default_cd: int, default_windup: int) -> int:
	var cd := int(row.get(specific_cd_key, 0))
	if cd > 0:
		var windup := int(row.get(specific_windup_key, 0))
		if windup <= 0:
			windup = int(row.get("windup_ticks", 0))
		if windup <= 0:
			windup = default_windup
		return _scaled_attack_ticks(maxi(cd - windup, 0))
	return _attack_cooldown_ticks(default_cd, default_windup)

## 原型取玩家位置；未注入 player_ref（纯 brain 测试）时退化为自身位置（零向量方向，不移动）。
func _player_pos() -> Vector2:
	return player_ref.brain_pos if player_ref != null else brain_pos

# ---- 物理表现层（手动验证；测试直接驱动 brain，不经此处） ----
func _physics_process(_delta: float) -> void:
	if state == State.DEAD:
		return
	# fix1：非有限坐标守卫（见 ensure_finite_position）——重置拍跳过表现层，
	# 权威位与实际位同拍归正，NaN/inf 不跨拍存活。
	if not ensure_finite_position():
		return
	update_vision_outlines(Engine.get_physics_frames())   # m4-c3：视界系描边每拍维护
	if player_ref != null and state == State.IDLE \
			and global_position.distance_to(player_ref.brain_pos) <= VISION_PX:
		on_player_seen(Engine.get_physics_frames())
	# brain_pos 为权威位置：以差值速度过 move_and_slide 处理碰撞，之后把 brain 对齐实际位置
	# m3-fix1 试炼 enemy_speed_pct 消费端：体速整体 ×TrialMods.enemy_speed_scale()
	# （×1.0 为 IEEE 精确恒等，非试炼局逐字节零漂移）。
	velocity = (brain_pos - global_position) * (TimeConst.FPS * TrialMods.enemy_speed_scale())
	move_and_slide()
	brain_pos = global_position
	# m0-t12 fix1：接触伤害（收口 t10 缺口）。玩家侧 0.8s 受击无敌帧天然节流同体连击，不另设冷却；
	# 距离用敌方实际位 vs player_ref.brain_pos（PlayerProxy 每拍镜像）。
	if player_ref != null and int(row.get("contact_dmg", 0)) > 0 \
			and global_position.distance_to(player_ref.brain_pos) <= combat_radius() + 6.0:
		var dealt := int(row["contact_dmg"])
		player_ref.take_hit({
			"amount": dealt, "is_crit": false,
			"element": _contact_element(), "from": global_position,
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
				# J4 tick 跳字色（M3 J-C 上报：表现层附加键，apply_hit_context 不读，判定零影响）
				"tick_element": Elements.Id.FIRE if status.active.has(Elements.Id.FIRE) else Elements.Id.POISON,
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
