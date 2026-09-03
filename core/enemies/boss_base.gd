class_name BossBase
extends EnemyBase
## Boss 三阶段框架（GDD §15）：行数据 "phases":[1.0,0.6,0.3]（血量分数，降序）解析为绝对血线；
## 血量下跨线 → 阶段只进不退 + 72t 转换无敌窗 + EventBus.boss_phase 广播 + _on_phase_enter 钩子。
## 子类照常写 _engage(frame)，按 phase() 分支；_on_engage_start 钩子原样继承。

const PHASE_INVULN_TICKS := 72   # 1.2s 阶段转换无敌窗
const PHASE_HITSTOP_MS := 120
const PHASE_SHAKE_PX := 6.0
const PHASE_SHAKE_SECONDS := 0.25
const PHASE_FLASH_SECONDS := 0.25

var _phase := 0
var _phase_thresholds: Array[int] = []   # 绝对血量线（floor(row.hp × 分数)），下标即阶段
var _phase_invuln_until := -1

## J7 Boss 死亡演出链驱动源：任一 BossBase 子类死亡恰发一次
## （四个真 Boss 覆写 die() 均调 super；vine_colossus/starfall_prophet 继承本类 die）。
signal boss_defeated(boss: BossBase)


## J-A：先广播死亡演出信号再走基类退场（基类状态门防重复；queue_free 延迟帧末，
## 监听者可读位置）。演出链的 Fx 请求在房间层击杀缝（floor_scene kill_kind=="boss"），
## 纯脑测 Boss 不在树内、不触发任何表现。
func die() -> void:
	if state == State.DEAD:
		return
	boss_defeated.emit(self)
	super()

func _test_init(r: Dictionary) -> void:
	super(r)          # 基类初始化（BossBase/子类脚本不触发原型换装，无实例重绑问题）
	_parse_phases(r)

## 行内血量分数 → 绝对血线（向下取整）。无 "phases" 行退化为单阶段 [hp]（框架对普通行安全）。
func _parse_phases(r: Dictionary) -> void:
	_phase = 0
	_phase_invuln_until = -1
	_phase_thresholds.clear()
	var total := float(r.get("hp", 10))
	for frac in r.get("phases", [1.0]):
		_phase_thresholds.append(int(floor(float(frac) * total)))

func phase() -> int:
	return _phase

## hp 所在阶段：从最深血线往回找第一条 hp<=线 的下标；均不满足（满血以上）为 0。
func _phase_for_hp(hp_value: int) -> int:
	for i in range(_phase_thresholds.size() - 1, -1, -1):
		if hp_value <= _phase_thresholds[i]:
			return i
	return 0

func take_hit(ctx: Dictionary) -> void:
	_take_hit_at(ctx, Engine.get_physics_frames())

## 可注入帧接缝（同 player.take_hit_ctx 模式）：阶段无敌窗按物理帧判定，headless 测试可注入帧。
## 基类 take_hit 的伤害体在此复写并在扣血后、死亡判定前插入血线检查——
## super(ctx) 无法在「死亡判定」前落钩，故不经 super（EnemyBase.take_hit 体小且稳定）。
func _take_hit_at(ctx: Dictionary, frame: int) -> void:
	if state == State.DEAD:
		return
	if frame < _phase_invuln_until:
		return   # 阶段转换无敌窗：不掉血、不闪白（死亡亦不可经此窗达成——门在扣血前返回）
	var hp_before := maxi(hp, 0)
	var amount := int(ctx["amount"])
	if status != null:
		amount = 0 if amount <= 0 else maxi(1, int(floor(float(amount) * status.damage_multiplier(frame))))
	var actual := mini(maxi(amount, 0), hp_before)
	var resolved := ctx.duplicate()
	resolved["amount"] = actual
	hp = hp_before - actual
	EventBus.enemy_damaged.emit(actual, bool(ctx.get("is_crit", false)))
	if _is_player_damage(ctx):
		EventBus.player_damage_resolved.emit(actual, frame)
	_advance_phase_if_crossed(frame)
	Fx.on_enemy_hit(self, resolved)
	if status != null:
		status.apply_hit_context(resolved, actual, frame)
		_consume_status_events(frame)
	if hp <= 0:
		die()

## 血线下跨线 → 推进阶段（只进不退，hp 回升/零伤天然不触发）、开无敌窗、广播、进钩子。
func _advance_phase_if_crossed(frame: int) -> void:
	var p := _phase_for_hp(hp)
	if p <= _phase:
		return
	_phase = p
	_phase_invuln_until = frame + PHASE_INVULN_TICKS
	# 纯脑测的 Boss 不在场景树，此时只验证阶段逻辑，不应暂停整个
	# GdUnit 树。生产实例入树后才执行重震、全屏闪光与 120ms hitstop。
	if is_inside_tree():
		# Fx.shake 在树暂停时按 Juice v1.5 契约早退，故必须先落重震再启 hitstop。
		Fx.shake("shake_boss_phase")   # J2 v2：来源表注入（+0.5），仍须先于 hitstop
		_phase_flash()
		Fx.request_boss_phase()   # J-A：120ms 冻结 + 0.3× 慢速 240ms（参数在 balance.json juice）
		AudioMgr.play("boss_phase")   # m4p-w2a：阶段切换拍（100%/60%/30% 血线，只进不退）
	EventBus.boss_phase.emit(self, _phase)
	_on_phase_enter(_phase)


## Boss 阶段全屏白闪：独立 CanvasLayer 避开 Fx 共享热点；PROCESS_MODE_ALWAYS +
## ignore_time_scale timer 确保 120ms hitstop 冻结期间仍可见，并在 0.25s 后回收。
func _phase_flash() -> void:
	if not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.name = "BossPhaseFlash"
	layer.layer = 1000
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1.0, 1.0, 1.0, 0.82)
	layer.add_child(flash)
	get_tree().root.add_child(layer)
	get_tree().create_timer(PHASE_FLASH_SECONDS, true, false, true).timeout.connect(
		func() -> void:
			if is_instance_valid(layer):
				layer.queue_free())

## 阶段进入钩子：子类覆写（换弹幕/位移模式等）；基类无操作。
func _on_phase_enter(_phase_idx: int) -> void:
	pass
