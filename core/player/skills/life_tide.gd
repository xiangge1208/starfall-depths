class_name LifeTide
extends SkillBase
## 守护者·萄 主动技「生命潮汐」（M2-T11 计划卡 + GDD §6 技能表守护者行）。
## CD 840t（14s；heroes 行 skill_cd 经 setup 覆写）、耗蓝 30（GDD §6）。
## 施放 → 立即回 2 HP + 在施放位置生成 180t（3s）静止治疗法阵（GDD §6）：
## - 治疗：每 60t（1s）法阵内玩家积累 0.5 HP；整数 HP 口径经累加器满 1 才落地——
##   3s 名义 1.5 HP，实落地 1 HP（第 2 秒拍生效），余 0.5 随法阵消散（不跨施放携带）；
## - 升级版（heroes 行 upgraded，GDD §6 强化列）：法阵内额外 -20% 受伤——
##   经 player.tide_guard_until 减伤窗（同狂潮 rampage_active_until 先例，×0.8
##   向下取整 min 1）；留在阵内每拍 +2 续窗，离阵/法阵结束后 ≤2 拍自然过期。
## 法阵半径 60px：GDD §6 未给半径，议定值（同坚守 60px AoE 先例；T28 Balance Bot 校准点）。
## 生产侧 _physics_process 自驱 tick（同 SummonBase 习语）；测试可注入任意帧直驱。
## 被动「祝福」（passive_id=blessing，m4-c2 接线）：每进入新层回满护盾 + 5% 全伤害
## （单局叠至 4 层），消费点 = run_root 层入口钩子（_apply_floor_entry_passives）+
## player.scaled_damage 玩家伤害出口聚合点。

const INSTANT_HEAL := 2             # 立即回 2 HP（GDD §6）
const DURATION_TICKS := 180         # 法阵持续 3s（GDD §6；末拍含——第 3 秒节拍在窗内）
const HEAL_INTERVAL_TICKS := 60     # 治疗节拍 1s（GDD §6「每秒」）
const HEAL_PER_TICK := 0.5          # 0.5 HP/s（GDD §6；整数 HP 经累加器落地）
const RADIUS_PX := 60.0             # 议定值（GDD §6 未给法阵半径）
const GUARD_LOOKAHEAD_TICKS := 2    # 减伤窗续期前瞻：覆盖同拍 tick/受击的节点处理序

var upgraded := false
var _center := Vector2.ZERO         # 法阵锚点（施放位置，静止不动）
var _until := -1                    # 法阵结束帧（含）；<0 = 无法阵
var _next_heal_at := -1
var _heal_acc := 0.0                # 0.5 HP 累加器（满 1 落地；法阵结束余数消散）

func _init() -> void:
	cooldown_ticks = 840        # 14s（GDD §6；数据行覆写）
	energy_cost = 30

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 法阵是否仍在窗内（测试/HUD 查询用；末拍含）。
func circle_active(frame: int) -> bool:
	return frame <= _until

func _activate(frame: int) -> void:
	if player == null:
		return
	AudioMgr.play("heal_tide")   # m4p-w2a：潮汐施放拍（cast 过门后到此才响）
	player.heal(INSTANT_HEAL)
	_center = player.global_position
	_until = frame + DURATION_TICKS
	_next_heal_at = frame + HEAL_INTERVAL_TICKS
	_heal_acc = 0.0
	if upgraded and _player_inside():
		player.tide_guard_until = frame + GUARD_LOOKAHEAD_TICKS

## 每拍推进：升级减伤窗续期 + 法阵节拍治疗。法阵结束/非节拍帧零分配零距离查询直接返回。
func tick(frame: int) -> void:
	if _until < 0 or frame > _until:
		return
	if upgraded and _player_inside():
		player.tide_guard_until = frame + GUARD_LOOKAHEAD_TICKS
	if frame < _next_heal_at or _next_heal_at > _until:
		return
	_next_heal_at += HEAL_INTERVAL_TICKS
	if not _player_inside():
		return                          # 阵外节拍空转（累加器不推进——治疗以「站在阵内」为前提）
	_heal_acc += HEAL_PER_TICK
	if _heal_acc >= 1.0:
		var whole := int(_heal_acc)     # 0.5 步进下恒为 1（二进制精确，无浮点漂移）
		player.heal(whole)
		_heal_acc -= float(whole)

func _player_inside() -> bool:
	return player != null and player.global_position.distance_to(_center) <= RADIUS_PX

## 生产自驱（同 SummonBase 习语）；无头测试直接调 tick(frame) 注入帧。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
