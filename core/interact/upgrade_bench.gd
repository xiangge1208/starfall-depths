class_name UpgradeBench
extends Interactable
## 局内武器升级台（M5-E，对标复盘 #5；每层固定 1 台，与熔铸台同房错位——
## floor_scene._build_shop 放置）。E 交互升级**当前手持武器**：+8% 伤害/级，
## 每把武器至多 3 级，价 35/55/80 递增（按当前级数取 PRICES[up_level]）。
##
## 状态载体：武器**实例**字典新键 `up_level`（equip 产出副本上，与 m5-c 的
## attachments 键并列；跨层随玩家实例存续——RunRoot 单次生成玩家、逐层复用）。
## GameDB 共享缓存零污染护栏与 m5-c 同款：equip 产出的实例恒带 attachments 键，
## 缺键 = run_root 对账路径直塞的共享行——写入前先 deep-copy 换回槽位。
##
## 浮标文案随级数/价格变化（「升级 短弓（55金）」/「已满级」）。满级 can_interact=false
## 隐藏浮标（ReviveTotem 充能后同款语义）；空槽（手刀态）同样不可交互。
## 伤害消费端在 player.scaled_damage 入口（插点披露见 player.gd / 提交体）。

const MAX_LEVEL := 3
const PRICES: Array[int] = [35, 55, 80]   # 索引 = 当前级数（0/1/2 → 升到 1/2/3 级）
const LABEL_MAXED := "已满级"

var wallet = null                         # duck-typed：spend_coins(n) -> bool（T14 契约）

func _ready() -> void:
	super()
	mount_facility_sprite("upgrade_bench")   # m4p-u2 设施贴图缝；暂无表项 fail-soft 色块

## 缺图回落色块表现（台身+台面+金饰条；零机制含义，贴图接线留给美术卡——
## art_lookup.gd 非本卡所有权）。
func _draw() -> void:
	draw_rect(Rect2(-9, -2, 18, 8), Color(0.35, 0.38, 0.45))
	draw_rect(Rect2(-11, -6, 22, 5), Color(0.55, 0.58, 0.66))
	draw_rect(Rect2(-11, -6, 22, 2), Color(0.9, 0.75, 0.3))

## 门控 + 浮标刷新（pick_best 每拍对候选调 can_interact——文案在此保持实时：
## 手持武器/级数变化无需本台自行轮询；prompt.bind 同拍读 action_label）。
func can_interact(player: Node2D) -> bool:
	var w := _held(player)
	if w.is_empty():
		return false
	_refresh_label(w)
	return int(w.get("up_level", 0)) < MAX_LEVEL

func interact(player: Node2D) -> void:
	var rig := _rig(player)
	if rig == null:
		return
	var w := rig.current()
	if w.is_empty():
		return
	var lvl := int(w.get("up_level", 0))
	if lvl >= MAX_LEVEL:
		return
	if wallet == null or not wallet.spend_coins(PRICES[lvl]):
		return                              # 金币不足：无浮标变化，金币 HUD 即反馈（图腾同款）
	# m5-c 零污染护栏同款（weapon_rig.apply_attachment 先例）：缺 attachments 键
	# = 对账路径直塞的 GameDB 共享行——先 deep-copy 换回槽位再写 up_level。
	if not w.has("attachments"):
		w = w.duplicate(true)
		w["attachments"] = {}
		rig.slots[rig.slot] = w
	w["up_level"] = lvl + 1                 # 实例字段即时生效，不写回 GameDB 行
	_refresh_label(w)
	AudioMgr.play("ui_buy")                 # m4p-w2a：购买成功拍（商店/图腾共用成功点）

func _held(player: Node2D) -> Dictionary:
	var rig := _rig(player)
	return {} if rig == null else rig.current()

func _rig(player: Node2D) -> WeaponRig:
	var p := player as Player
	return p.weapon_rig if p != null and p.weapon_rig != null else null

func _refresh_label(w: Dictionary) -> void:
	var lvl := int(w.get("up_level", 0))
	var text := LABEL_MAXED if lvl >= MAX_LEVEL \
		else "升级 %s（%d金）" % [String(w.get("name", "?")), PRICES[lvl]]
	if text != action_label:
		action_label = text
