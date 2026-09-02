extends EnemyBase
## 重装（附录 B 原型「重装」）：缓慢逼近玩家，正面扇区（朝向 ±90°）减伤
## front_block_pct（硬壳龟 0.8 / 黑曜卫 0.8 / 磁石傀儡·冻土巨蟹 0.6 / 老树守卫 0.5）；
## 背面/侧面全伤（「侧面可击」）。带弹行（老树守卫 弹4）每 cd_ticks 蓄力 windup 后
## 释放根部弹环（volley_count 均布）。
## 面向 = 逼近方向（每拍刷新）；受击方向取 ctx["from"]（来弹位）。
##
## m4-c1 派味特技（行键门控，无键行逐行为零变化）：
## - 龟缩（硬壳龟，shell_walk_ticks/shell_up_ticks）：周期免疫窗——ENGAGE 后行走
##   shell_walk_ticks → 缩壳 shell_up_ticks（全向免疫 + 停止移动，缩壳语义）→ 循环。
##   周期态而非永久（房间可清不变量：免疫窗有界且必然让位于行走窗）。锚定 ENGAGE
##   转换拍（确定性，不漂工程帧）。正面减伤 0.8 在非缩壳期原样生效（其上叠加）。
## - 拉拽（磁石傀儡，pull_* 键）：周期 windup 预警 → 把 pull_range_px 内玩家向自身
##   位移 pull_px（2 格，经 PlayerProxy.apply_pull，尊重玩家无敌帧/翻滚窗）→ 冷却。
## - 钳击（冻土巨蟹，claw_* 键）：周期 windup 预警（§7.5 ≥0.35s）→ 横扫：面向扇区
##   claw_range_px 内玩家吃 claw_dmg 高伤（ICE 归因）→ 冷却。

const DEFAULT_VOLLEY_COUNT := 8
const RING_SPEED_DEFAULT := 95.0

var _facing := Vector2.RIGHT
var _phase := "idle"
var _phase_left := 0

# ---- m4-c1 龟缩（周期免疫窗）----
var _shell_walk_until := -1     # 行走窗截止帧（含）；<0 = 未进入周期（ENGAGE 前不龟缩）
var _shell_until := -1          # 缩壳免疫窗截止帧（ Exclusive：>frame 表示窗内）

# ---- m4-c1 拉拽 ----
var _pull_phase := "idle"
var _pull_left := 0

# ---- m4-c1 钳击 ----
var _claw_phase := "idle"
var _claw_left := 0
var _claw_facing := Vector2.RIGHT   # 横扫扇区锚定朝向（windup 起始拍锁定——预警扇区可躲）


func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	if to_player.length_squared() > 0.0001:
		_facing = to_player.normalized()
	if not _shell_holds(frame):
		brain_pos += _facing * (float(row.get("speed", 30)) / TimeConst.FPS)
	_tick_shell(frame)
	_tick_pull(frame)
	_tick_claw(frame)
	if int(row.get("bullet_dmg", 0)) <= 0:
		return                                   # 纯贴近型重装（硬壳龟等）无弹环
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_root_ring(frame)
				_phase = "cool"
				_phase_left = _attack_cooldown_ticks(180)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})


func _on_engage_start(frame: int) -> void:
	if int(row.get("shell_up_ticks", 0)) > 0 and int(row.get("shell_walk_ticks", 0)) > 0:
		_shell_walk_until = frame + int(row["shell_walk_ticks"])


## 缩壳免疫窗判定（ENGAGE 后周期：行走 walk → 缩壳 up → 行走 walk → …）。
func _shell_holds(frame: int) -> bool:
	return frame < _shell_until


func _tick_shell(frame: int) -> void:
	if _shell_walk_until < 0:
		return                                   # 无键或未 ENGAGE：周期未建立
	if frame < _shell_until:
		return                                   # 缩壳窗内（免疫 + 停走已由 _shell_holds 承担）
	if frame >= _shell_walk_until:
		_shell_until = frame + int(row.get("shell_up_ticks", 0))
		_shell_walk_until = _shell_until + int(row.get("shell_walk_ticks", 0))
		Fx.on_enemy_hit(self, {"telegraph": true})   # 缩壳起步闪提示（免疫窗可读性）
		Telemetry.log_row(["enemy_shell_up", frame, int(row["shell_up_ticks"])],
			String(row.get("id", "")))


## 拉拽周期（idle→windup→拉→cool→…）。
func _tick_pull(frame: int) -> void:
	if int(row.get("pull_px", 0)) <= 0:
		return
	match _pull_phase:
		"idle":
			_pull_phase = "windup"
			_pull_left = _signature_windup("pull_windup_ticks", 30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_pull_left -= 1
			if _pull_left <= 0:
				_do_pull(frame)
				_pull_phase = "cool"
				_pull_left = _signature_cooldown("pull_cd_ticks", "pull_windup_ticks",
					180, 30)
		"cool":
			_pull_left -= 1
			if _pull_left <= 0:
				_pull_phase = "windup"
				_pull_left = _windup_ticks(int(row.get("pull_windup_ticks", 30)))
				Fx.on_enemy_hit(self, {"telegraph": true})


## 拉拽执行：range 内玩家向自身位移 pull_px（目标点钳房间内域；apply_pull 尊重无敌帧）。
func _do_pull(frame: int) -> void:
	if player_ref == null or not player_ref.has_method("apply_pull"):
		return
	var player_pos: Vector2 = _player_pos()
	var to_golem := brain_pos - player_pos
	if to_golem.length() > float(row.get("pull_range_px", 0.0)):
		return
	var dir := to_golem.normalized() if to_golem.length_squared() > 0.0001 else Vector2.ZERO
	if dir == Vector2.ZERO:
		return
	var target := _clamp_to_bounds(player_pos + dir * float(row["pull_px"]))
	if player_ref.apply_pull(target):
		Telemetry.log_row(["enemy_pull", frame, int(row["pull_px"])],
			String(row.get("id", "")))


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	if combat_bounds.size == Vector2.ZERO:
		return pos
	var inset := 6.0                      # 玩家名义半径（防贴墙出界）
	var legal := Rect2(combat_bounds.position + Vector2.ONE * inset,
		combat_bounds.size - Vector2.ONE * inset * 2.0)
	return Vector2(clampf(pos.x, legal.position.x, legal.end.x),
		clampf(pos.y, legal.position.y, legal.end.y))


## 钳击周期（idle→windup→横扫→cool→…）。扇区朝向在 windup 起始拍锁定（预警扇区
## 「指哪打哪」——玩家在 windup 内离开锁定扇区/射程即可躲，语义与 task-9 原表一致）。
func _tick_claw(frame: int) -> void:
	if int(row.get("claw_dmg", 0)) <= 0:
		return
	match _claw_phase:
		"idle":
			_claw_phase = "windup"
			_claw_left = _signature_windup("claw_windup_ticks", 30)
			_claw_facing = _facing
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_claw_left -= 1
			if _claw_left <= 0:
				_claw_sweep(frame)
				_claw_phase = "cool"
				_claw_left = _signature_cooldown("claw_cd_ticks", "claw_windup_ticks",
					240, 30)
		"cool":
			_claw_left -= 1
			if _claw_left <= 0:
				_claw_phase = "windup"
				_claw_left = _signature_windup("claw_windup_ticks", 30)
				_claw_facing = _facing
				Fx.on_enemy_hit(self, {"telegraph": true})


## 横扫结算：windup 起始锁定的扇区朝向 ±arc/2、range+6px（玩家名义半径）内玩家吃
## claw_dmg 高伤（ICE 归因）。经 take_hit → 玩家侧无敌帧/护盾既有语义天然生效；
## i 帧内拍点打空也照常进冷却。
func _claw_sweep(frame: int) -> void:
	if player_ref == null or not player_ref.has_method("take_hit"):
		return
	var to_player: Vector2 = _player_pos() - brain_pos
	var reach := float(row.get("claw_range_px", 0.0)) + 6.0
	var hit := false
	if to_player.length() <= reach:
		var half_arc := deg_to_rad(float(row.get("claw_arc_deg", 120.0))) * 0.5
		if to_player.length_squared() < 0.0001 \
				or absf(_claw_facing.angle_to(to_player)) <= half_arc:
			player_ref.take_hit({
				"amount": int(row["claw_dmg"]), "is_crit": false,
				"element": Elements.Id.ICE, "from": brain_pos,
				"source_type": "melee_enemy", "source_id": String(row.get("id", "")),
				"source_name": String(row.get("name", row.get("id", ""))),
				"attack_name": "钳击横扫",
			})
			hit = true
	Telemetry.log_row(["claw_sweep", frame, 1 if hit else 0], String(row.get("id", "")))


## 根部弹环（B.2 A1 老树守卫「根部弹环」）：以自身为中心 volley_count 发均布环弹。
func _fire_root_ring(_frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var count := int(row.get("volley_count", DEFAULT_VOLLEY_COUNT))
	for i in count:
		var dir := Vector2.from_angle(TAU * float(i) / float(count))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": dir * enemy_bullet_speed(RING_SPEED_DEFAULT),
			"damage": int(row.get("bullet_dmg", 4)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "根部弹环",
		})

## 正面减伤：来弹方向与面向同侧（点积 > 0）时按 front_block_pct 削减；其余全伤。
## m4-c1 龟缩：缩壳免疫窗内全向 0 伤（叠加在正面减伤之上——窗口优先，正面/背面同免）。
func take_hit(ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	var frame := int(ctx.get("frame", Engine.get_physics_frames()))
	if _shell_holds(frame):
		var immune := ctx.duplicate()
		immune["amount"] = 0
		super(immune)
		return
	var block := _effective_block_pct(frame)
	if block > 0.0:
		var from: Vector2 = ctx.get("from", brain_pos)
		var incoming := from - brain_pos
		if incoming.length_squared() > 0.0001 and _facing.dot(incoming.normalized()) > 0.0:
			var reduced := ctx.duplicate()
			# round 而非 floor：0.8 减伤在浮点下 10×0.2=1.999…，floor 会多砍 1
			reduced["amount"] = int(round(float(int(ctx.get("amount", 0))) * (1.0 - block)))
			super(reduced)
			return
	super(ctx)

## 生效正面减伤比例（子类覆写钩子：石盾武僧破势窗内归零）。
func _effective_block_pct(_frame: int) -> float:
	return float(row.get("front_block_pct", 0.0))
