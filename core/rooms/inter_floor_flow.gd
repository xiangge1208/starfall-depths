class_name InterFloorFlow
extends RefCounted
## 层间流程状态机（m1-t20，纯逻辑无头可测）：Boss 死亡后的中转顺序
##   BUFF（增益三选一，复用 T9 BuffManager.roll_three / pick）
##   → FOUNTAIN（治疗喷泉：免费回 2 HP，仅一次）
##   → DOOR（下一层门：RunState.next_floor() 推层并结算蓝晶）→ DONE。
## 第 3 层（floor_idx >= 3）Boss 后直接胜利：置 victory 旗并发 victory_achieved
## （m2-t18 真实触发，RunRoot 接信号切胜利结算场景；重复 open 幂等只首触发一次）。
##
## 乞丐 payout 接缝（T19 规格，duck-typed 防御）：DOOR 阶段 advance() 时若
## RunState.pending_investment > 0 且 beggar_paid_floor == floor_idx，
## 以注入 rng 掷 70%：命中 → coins += pending；无论命中与否 pending/paid_floor 结清
## （返还或打水漂，投资在层门处一次性了结；_payout_resolved 保证每门只结一次）。
## 字段缺失时整缝静默跳过（`"field" in RunState` 探测），不阻塞层间流程。

enum Phase { BUFF, FOUNTAIN, DOOR, DONE }

## m2-t18 胜利触发：第 3 层 Boss 后 open_with_offerings 走胜利分支时发出
## （宿主 RunRoot 接线 → SceneRouter 切 victory 结算场景；本类保持纯逻辑无头）。
signal victory_achieved

const FOUNTAIN_HEAL := 2        # GDD §11：治疗喷泉免费回 2 HP
const VICTORY_FLOOR := 3        # GDD §4.2：第 3 层 Boss 后胜利（m2-t18 起发 victory_achieved）
const PAYOUT_CHANCE := 0.7      # 乞丐投资返还概率（T19 规格）

var phase: int = Phase.BUFF
var floor_idx := 1
var victory := false
var offered: Array[String] = []     # 本次三选一名录（choose_buff 白名单）
var fountain_used := false
var buffs_manager: BuffManager = null

var _offer_rng: RandomNumberGenerator      # open_with_offerings 注入；payout 兜底续抽
var _payout_resolved := false
## payout 掷签流（可注入替换，测试钉死赢/输两路）；null 时复用 _offer_rng 续抽。
var payout_rng: RandomNumberGenerator = null


## 绑定楼层与增益管理器：流程从 BUFF 站起（offered 空 → choose_buff fail-closed）。
func setup(p_floor_idx: int, p_buffs: BuffManager) -> void:
	floor_idx = p_floor_idx
	buffs_manager = p_buffs
	phase = Phase.BUFF


## Boss 死亡触发：掷三选一 → BUFF；第 3 层 → victory_achieved 触发并跳过全部阶段
## （返回空名录；victory 旗幂等守卫保证信号只发一次，重复 open 不重发防双结算）。
## 抽池空（roll_three 返回 []）→ 跳过 BUFF 直进 FOUNTAIN（防软锁）。
func open_with_offerings(rng: RandomNumberGenerator) -> Array[String]:
	if floor_idx >= VICTORY_FLOOR:
		if not victory:
			victory = true
			victory_achieved.emit()
		phase = Phase.DONE
		offered = []
		return []
	_offer_rng = rng
	offered = buffs_manager.roll_three(rng)
	phase = Phase.FOUNTAIN if offered.is_empty() else Phase.BUFF
	return offered


## 选增益：仅 BUFF 阶段且 id ∈ 本次三选（fail-closed）；经 buffs_manager.pick 落地。
func choose_buff(id: String) -> bool:
	if phase != Phase.BUFF or not offered.has(id):
		return false
	if buffs_manager != null:
		buffs_manager.pick(id)
	phase = Phase.FOUNTAIN
	return true


## 治疗喷泉：仅 FOUNTAIN 阶段、仅一次；免费 heal(2) → DOOR（advance 结门侧效）。
func use_fountain(p: Player) -> bool:
	if phase != Phase.FOUNTAIN or fountain_used:
		return false
	if p == null:
		push_error("InterFloorFlow.use_fountain: player is null")
		return false
	fountain_used = true
	p.heal(FOUNTAIN_HEAL)
	phase = Phase.DOOR
	advance()
	return true


## 下一层门：仅 DOOR 阶段；RunState.next_floor()（推层 + §14.1 蓝晶结算）→ DONE。
## 非法阶段返回 -1 且不动 RunState（跳步进门 fail-closed）。
func enter_next_floor() -> int:
	if phase != Phase.DOOR:
		return -1
	var new_floor := RunState.next_floor()
	phase = Phase.DONE
	return new_floor


## 阶段泵：处理当前阶段的自动侧效（DOOR：乞丐 payout，幂等只结一次）。
func advance() -> void:
	if phase == Phase.DOOR and not _payout_resolved:
		_payout_resolved = true
		_resolve_beggar_payout()


## 乞丐 payout：duck-typed get-or-default（T19 字段存在才读，缺失整缝跳过）。
func _resolve_beggar_payout() -> void:
	if not ("pending_investment" in RunState):
		return
	var pending := int(RunState.get("pending_investment"))
	if pending <= 0:
		return
	if not ("beggar_paid_floor" in RunState):
		return
	var paid := int(RunState.get("beggar_paid_floor"))
	# 事件房记的是「付款发生层」；当前层 Boss 后的 DOOR 正是进入下层前的结算点。
	if paid != floor_idx:
		return
	var roll_rng := payout_rng if payout_rng != null else _offer_rng
	if roll_rng != null and roll_rng.randf() < PAYOUT_CHANCE:
		RunState.add_coins(pending)
	RunState.set("pending_investment", 0)   # 命中与否都结清（一次性了结）
	RunState.set("beggar_paid_floor", 0)
