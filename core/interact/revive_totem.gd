class_name ReviveTotem
extends Interactable
## 复活图腾（M5-A1，GDD §14.2「复活图腾（一次性，Boss 房前）150」落地；对标复盘 #1）。
## 放置于小 Boss 房（Boss 主路径倒数第二节点，字面「Boss 房前」；嘉宾战斗房
## 「无设施」惯例的唯一例外——本设施即为该点位而设计，见 floor_scene 放置注）。
##
## 购买：E 交互扣 150 金 → RunState.revive_charged = true（局内一次性；start_run
## 重置）。已充能后 can_interact=false 隐藏浮标（贴图增亮表状态）。
## 触发：玩家致命伤时（player.take_hit_ctx）消耗标记原地复活——复活逻辑在玩家
## 受击结算收口，本类只负责售卖。

const COST := 150

var _charged_fx := false

func _ready() -> void:
	super()
	mount_facility_sprite("totem_revive")     # m4p-u2 设施贴图缝；缺图 fail-soft

func can_interact(_player: Node2D) -> bool:
	return not RunState.revive_charged

func interact(_player: Node2D) -> void:
	if RunState.revive_charged:
		return
	if not RunState.spend_coins(COST):
		return                                 # 金币不足：无浮标变化，金币 HUD 即反馈
	RunState.revive_charged = true
	_charged_fx = true
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr != null:
		spr.modulate = Color(1.6, 1.6, 1.1)    # 充能增亮（单贴图两态的最小表现）
	AudioMgr.play("ui_buy")
