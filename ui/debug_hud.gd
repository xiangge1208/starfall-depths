class_name DebugHUD
extends CanvasLayer
## DEBUG HUD（m0-t12）：FPS / 实体数 / 活跃弹幕 / 玩家无敌帧 / 清房计时 / 金币。
## 调试用途（非正式 UI）：PROCESS_MODE_ALWAYS 保证 hitstop 暂停中仍刷新。

var player: Player
var combat: CombatSystem
var room: RoomCombat

var _label: Label

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(4, 2)
	_label.add_theme_font_size_override("font_size", 8)
	add_child(_label)

func _process(_delta: float) -> void:
	var lines: Array[String] = []
	lines.append("[DEBUG] FPS:%d" % Engine.get_frames_per_second())
	var bullets := 0
	if combat != null:
		bullets = combat.active_count()
	lines.append("entities:%d bullets:%d" % [_count_enemies(), bullets])
	if player != null:
		lines.append("hp:%d/%d sh:%d iframe:%s" % [
			player.hp, player.hp_max, player.shield, str(player.is_invincible()),
		])
	if room != null:
		var t := 0.0
		if room.entry_frame >= 0:
			t = float(Engine.get_physics_frames() - room.entry_frame) / TimeConst.FPS
		lines.append("room:%s wave:%d clear_t:%.1fs coins:%d" % [
			room.room_id, room.flow.wave_index() + 1, t, room.coins_collected(),
		])
	_label.text = "\n".join(lines)

func _count_enemies() -> int:
	return get_tree().get_nodes_in_group("enemies").size()
