class_name Player
extends CharacterBody2D
## 玩家。手感常量集中此处（GDD §5.2）；其余数值读 GameDB/HUD 层。

const MOVE_SPEED := 80.0
const ACCEL := 1400.0
const FRICTION := 1800.0
const ROLL_TICKS := 13
const ROLL_DIST := 56.0
const ROLL_CD_TICKS := 42          # 0.7s
const HURT_IFRAME_TICKS := 48      # 0.8s
const SHIELD_DELAY_TICKS := 180    # 3.0s
const SHIELD_INTERVAL_TICKS := 72  # 1.2s/点
const RAMPAGE_DR := 0.7            # 狂潮(升级)：受伤 ×0.7（向下取整，min 1）
const TIDE_DR := 0.8               # 生命潮汐(升级)：法阵内受伤 ×0.8（向下取整，min 1；m2-t11）
const DEFIANCE_RADIUS_PX := 60.0   # 坚守：AoE 半径
const DEFIANCE_KNOCKBACK_PX := 8.0 # 坚守：击退距离
const DEFIANCE_STUN_TICKS := 30    # 坚守：眩晕 0.5s
# m4-c2 英雄被动 ×4 消费端数值（GDD §6 逐字）。
const BLESSING_STACK_CAP := 4             # 祝福：单局叠层上限（至多 4 层）
const BLESSING_DMG_PCT_PER_STACK := 0.05  # 祝福：每层 +5% 全伤害
const SHADOW_REAP_ENERGY := 5             # 掠影：近战击杀返还蓝量
const SHADOW_REAP_ROLL_FREE_TICKS := 60   # 掠影：击杀后翻滚免冷却窗（1s）
# m2-t26 灾厄「治疗无效」meta 键单一出处（FloorScene 挂载/摘除；heal() 前置拦截一切治疗源）
const CALAMITY_HEAL_DISABLED_META := "calamity_heal_disabled"
# m2-t35 meta 生效接线（裁定⑨）：T12 增益键消费读数。
# 击杀回蓝掷签独立盐（RngSvc.stream(floor_idx, salt) 接受任意盐串；常量就近声明，
# 不改 run_state.gd 的 SALT_* 表——该文件不在本卡文件所有权内）。
const SALT_KILL_ENERGY := "kill_energy"
# 不死鸟「每局 1 次」消费记号（独立于 buff_phoenix_flag 聚合 meta——后者会被
# BuffManager.apply_to_player 幂等绝对重写回 1，复活次数必须跨重 apply 存活）。
const PHOENIX_USED_META := "m2t35_phoenix_used"
# m2-t17 四向行走帧表：art/generated/characters/hero_<id>_sheet.png（64x64，
# 4 行=下/上/左/右 × 4 列=idle+walk×3，16px/帧）。帧序 = 方向行*4 + 列。
const ANIM_SHEET_COLS := 4
const ANIM_SHEET_ROWS := 4
const ANIM_SHEET_PATH_FMT := "res://art/generated/characters/hero_%s_sheet.png"
const ANIM_WALK_TICKS := 8         # 行走 8t/帧 → 三帧循环 7.5fps
const ANIM_DIR_DOWN := 0
const ANIM_DIR_UP := 1
const ANIM_DIR_LEFT := 2
const ANIM_DIR_RIGHT := 3

var hp := 8
var hp_max := 8
var shield := 4
var shield_max := 4
var energy := 100
var energy_max := 100
var move_speed := MOVE_SPEED
var facing := Vector2.RIGHT
# 局内永久/临时 modifier。Buff、饮料与雕像都写这些公开字段；生产消费者只读
# effective_*，避免先喝饮料/先选 Buff 的顺序改变结果。
var crit_bonus := 0.0
var crit_damage_bonus := 0.0
var status_rate_bonus := 0.0
var shield_delay_reduction_ticks := 0
var roll_cd_pct := 0.0
var roll_cd_reduction_ticks := 0
var move_speed_boost_pct := 0.0
var move_speed_boost_until := -1
var atk_speed_boost_pct := 0.0
var atk_speed_boost_until := -1
var energy_free_until := -1
var incoming_slow_pct := 0.0
var incoming_slow_until := -1
var weapon_rig: WeaponRig = null   # tscn 子节点（_ready 解析；测试可手工注入）
# m4-c2：房间 CombatSystem 引用（RoomCombat/FloorScene/训练房注入）。setter 把英雄
# 被动 id 回写到 combat（echo 伤害乘区读点）——floor_scene._wire_room_combat 每次进房
# 重注入时同步刷新；HeroApplier 装配晚于 combat 注入的次序由其侧兜底回填。
var combat: CombatSystem = null:
	set(value):
		combat = value
		if combat != null:
			combat.hero_passive_id = passive_id
var rampage_active_until := -1     # 狂潮(升级)减伤窗：frame < 此值时受伤 ×0.7（技能写入）
var tide_guard_until := -1         # 生命潮汐(升级)减伤窗：frame < 此值时受伤 ×0.8（技能每拍续写；m2-t11）
## m4-c3 复仇者（avenger）复仇窗终帧：受击落地时按 rig meta buff_vengeance_pct/ticks
## 开窗（take_hit_ctx 写入； CombatSystem 命中结算读窗 ×(1+pct)，GDD §7.1 全局乘区）。
var vengeance_until := -1
var has_defiance := false          # 被动「坚守」开关（角色数据注入，t11）
var passive_id := ""               # m4-c2：英雄被动 id（HeroApplier 注入；echo/blessing/spare_parts/shadow_reap 消费门控）
var blessing_stacks := 0           # m4-c2 祝福叠层（run_root 层入口写入；run 内持续，新局随玩家实例重建归零）
var friction_mult := 1.0           # m2-t4 冰面接缝：IceZone 进域写 0.25 / 出域回 1.0（MoveMath 摩擦参数临时替换）
var _roll_left := 0
var _roll_vel := Vector2.ZERO
var _roll_end_frame := -999
var _roll_cd_until := -999
var _reap_roll_free_until := -999  # m4-c2 掠影：翻滚免冷却窗终帧（默认 -999 → 非刺客路径零漂移）
var _iframe_until := -999
var _last_damaged_frame := -999
var _shield_next_at := -999
var _passive_energy_acc := 0       # m2-t35 弹药转化：被动回蓝拍累加器（interval meta 驱动）
var _kill_rng: RandomNumberGenerator = null   # m2-t35 蓝能汲取掷签流（RunState 分盐，惰性缓存）
# m2-t17 行走动画：帧表一次性缓存（hero_id → Texture2D/ null，非热路径）；
# _anim_seen_tex 用于识别进房重装（ArtLookup.apply_player_sprite 写回站立像）。
var _anim_sprite: Sprite2D = null
var _anim_sheet: Texture2D = null
var _anim_seen_tex: Texture2D = null
var _anim_dir := ANIM_DIR_DOWN
var _anim_frame := -1

static var _anim_sheet_cache: Dictionary = {}

func _test_init() -> void:
	# 纯逻辑测试入口：不进场景树也能测状态机
	pass

func _ready() -> void:
	if weapon_rig == null:
		weapon_rig = get_node_or_null("WeaponRig")
	_anim_sprite = get_node_or_null("Sprite") as Sprite2D
	_load_anim_sheet()
	EventBus.shield_broken.connect(_on_shield_broken)
	EventBus.enemy_killed.connect(_on_enemy_killed)   # m2-t35：蓝能汲取击杀挂钩

func _physics_process(_delta: float) -> void:
	var f := Engine.get_physics_frames()
	apply_anti_ice_friction()          # m2-t35：抗冰拍内强制不打滑（IceZone 写入后覆盖）
	passive_energy_tick(f)             # m2-t35：弹药转化被动回蓝
	var physical_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var touch_dir := Input.get_vector("touch_move_left", "touch_move_right",
		"touch_move_up", "touch_move_down")
	var dir := (physical_dir + touch_dir).limit_length(1.0)
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if _roll_left > 0:
		_roll_left -= 1
		velocity = _roll_vel
	else:
		if (Input.is_action_just_pressed("roll") or Input.is_action_just_pressed("touch_roll")) \
				and roll_ready_at(f):
			start_roll(dir if dir != Vector2.ZERO else facing, f)
		velocity = MoveMath.accelerate(velocity, dir, effective_move_speed(f), ACCEL,
			FRICTION * friction_mult)
	move_and_slide()
	_shield_tick(f)
	_update_walk_anim(dir, f)

func start_roll(dir: Vector2, frame: int) -> void:
	var d := dir.normalized()
	# m2-t35 冲刺延伸：翻滚距离 ×(1+buff_roll_distance_pct)（速度同步放大，tick 数不变）。
	var dist := ROLL_DIST * (1.0 + float(get_meta("buff_roll_distance_pct", 0.0)))
	_roll_vel = d * (dist / (float(ROLL_TICKS) / TimeConst.FPS))
	_roll_left = ROLL_TICKS
	_roll_end_frame = frame + ROLL_TICKS
	_roll_cd_until = _roll_end_frame + effective_roll_cd_ticks()
	Fx.on_roll(self)

# ---- m2-t17 四向行走动画（帧表驱动，纯整数运算零分配） ----

## 方向行号：主轴优先（|x|>=|y| 取横向），对角输入落横行；静止由调用方保留上一行。
static func anim_dir_index(dir: Vector2) -> int:
	if absf(dir.x) >= absf(dir.y):
		return ANIM_DIR_RIGHT if dir.x >= 0.0 else ANIM_DIR_LEFT
	return ANIM_DIR_DOWN if dir.y >= 0.0 else ANIM_DIR_UP

## 行走循环列（1..3，8t/帧）；idle 恒列 0。
static func anim_walk_col(frame: int) -> int:
	return 1 + int(floor(float(frame) / ANIM_WALK_TICKS)) % 3

## 帧序号纯函数：dir 为移动输入（ZERO=idle，沿用 last_dir 行）。
static func anim_frame_index(dir: Vector2, last_dir: int, frame: int) -> int:
	var row := last_dir
	if dir != Vector2.ZERO:
		row = anim_dir_index(dir)
	var col := 0
	if dir != Vector2.ZERO:
		col = anim_walk_col(frame)
	return row * ANIM_SHEET_COLS + col

## 帧表装配：hero meta → hero_<id>_sheet.png（ArtLookup.tex 缓存载入，一次性）。
## 缺表（新英雄未出帧表）回落 hframes=1 单帧＝ArtLookup.apply_player_sprite 的站立像。
func _load_anim_sheet() -> void:
	if _anim_sprite == null:
		return
	var hero_id := "vanguard"
	if has_meta("hero"):
		hero_id = String((get_meta("hero") as Dictionary).get("id", hero_id))
	if not _anim_sheet_cache.has(hero_id):
		_anim_sheet_cache[hero_id] = ArtLookup.tex(ANIM_SHEET_PATH_FMT % hero_id)
	_anim_sheet = _anim_sheet_cache[hero_id]
	_apply_anim_texture()

func _apply_anim_texture() -> void:
	if _anim_sprite == null:
		return
	if _anim_sheet == null:
		_anim_sprite.hframes = 1          # 站立像单帧（帧表缺失英雄的回落）
		_anim_sprite.vframes = 1
		_anim_sprite.frame = 0
		_anim_frame = -1
		_anim_seen_tex = _anim_sprite.texture
		return
	_anim_sprite.texture = _anim_sheet
	_anim_sprite.hframes = ANIM_SHEET_COLS
	_anim_sprite.vframes = ANIM_SHEET_ROWS
	_anim_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim_seen_tex = _anim_sheet
	_anim_frame = -1

## 移动方向自动切行动画：进房被 apply_player_sprite 写回站立像（或 run_root 装配
## 晚于 _ready 落 meta）时按贴图同一性懒重解析；帧序只在变化时写 Sprite（零热路径分配）。
func _update_walk_anim(dir: Vector2, frame: int) -> void:
	if _anim_sprite == null:
		return
	if _anim_sprite.texture != _anim_seen_tex:
		_load_anim_sheet()
	if _anim_sheet == null:
		return
	if dir != Vector2.ZERO:
		_anim_dir = anim_dir_index(dir)
	var idx := anim_frame_index(dir, _anim_dir, frame)
	if idx != _anim_frame:
		_anim_sprite.frame = idx
		_anim_frame = idx

func roll_ready_at(frame: int) -> bool:
	# m4-c2 掠影（刺客被动）：免冷却窗内无视翻滚 CD（多次击杀顺延，窗口语义见 on_melee_kill）。
	return frame >= _roll_cd_until or frame < _reap_roll_free_until

func effective_roll_cd_ticks() -> int:
	return maxi(0, int(round(float(ROLL_CD_TICKS) * (1.0 + roll_cd_pct))) \
		- roll_cd_reduction_ticks)

## m4-c3 复仇者（avenger，GDD 附录 C「受击后 3s 内伤害 +25%」）：受击落地即按 rig
## buff_* meta 开复仇窗（pct ≤ 0 不开窗不读 ticks——无增益零开销零漂移；窗按最新
## 受击顺延，同 CombatSystem 命中结算读点 frame < vengeance_until）。节流天然由受击
## 无敌帧（0.8s）承担，非每帧路径。遥测 vengeance_trigger（Telemetry 既有清单无撞名）。
func _open_vengeance_window(frame: int) -> void:
	var rig := weapon_rig
	if rig == null:
		return
	var pct := float(rig.get_meta("buff_vengeance_pct", 0.0))
	if pct <= 0.0:
		return
	vengeance_until = frame + maxi(1, int(rig.get_meta("buff_vengeance_ticks", 0)))
	Telemetry.log_row(["vengeance_trigger", frame, pct])

## m4-c2 玩家伤害出口聚合点：远程（weapon_rig._fire_slot → talent_scaled_damage）与
## 近战挥击（melee.gd）统一经此乘区。乘区 = (1 + 天赋 talent_dmg_pct) × (1 + 祝福
## blessing_stacks×5%)，round 取整沿袭 m2-t35 天赋先例；GDD §7.1 最终「向下取整、最小 1」
## 在命中结算侧（DamageCalc.compute / CombatSystem 回响乘区）完成。
func scaled_damage(base: int) -> int:
	return int(round(float(base) * (1.0 + talent_effect_value("talent_dmg_pct")) \
		* (1.0 + float(blessing_stacks) * BLESSING_DMG_PCT_PER_STACK)))

## m4-c2 掠影（刺客被动，GDD §6）：近战击杀 → 返还 5 蓝 + 1s（60t）翻滚免冷却窗。
## 窗口按最新击杀顺延（frame+60）；被动门控在 Player（melee.gd 击杀路径只负责上报）。
## 翻滚自身仍写常规 CD（start_roll 语义不变）：窗内可连续翻滚，窗外恢复 0.7s 冷却。
func on_melee_kill(frame: int) -> void:
	if passive_id != "shadow_reap":
		return
	add_energy(SHADOW_REAP_ENERGY)
	_reap_roll_free_until = frame + SHADOW_REAP_ROLL_FREE_TICKS

## m2-t35 受击无敌帧：基线 ×(1+天赋 talent_hurt_iframe_pct) + 增益加算
## （nerve_reflex 的 hurt_iframe_bonus_ticks）。技能侧 apply_iframes 保持绝对 tick 语义不变。
func effective_hurt_iframe_ticks() -> int:
	return int(round(float(HURT_IFRAME_TICKS) * (1.0 + talent_effect_value("talent_hurt_iframe_pct")))) \
		+ int(get_meta("buff_hurt_iframe_bonus_ticks", 0))

## m2-t35：天赋聚合读数（TalentSystem.apply_to_player 落的 talent_effects meta；
## 未 apply/未购 → 0）。与 TalentSystem.effects_of 同义，但缺 meta 时不触发引擎
## get_meta 报错上屏（训练房/测试裸玩家热路径卫生，effects_of 的 null 默认值会刷 ERROR）。
func talent_effect_value(key: String) -> float:
	var te: Variant = get_meta("talent_effects", {})
	if typeof(te) == TYPE_DICTIONARY:
		return float((te as Dictionary).get(key, 0.0))
	return 0.0

## m2-t35 抗冰：冰面打滑免疫——拍内强制摩擦系数回 1.0（IceZone 进域写 0.25 后覆盖）。
func apply_anti_ice_friction() -> void:
	if int(get_meta("buff_anti_ice", 0)) == 1:
		friction_mult = 1.0

## m2-t35 弹药转化：每 interval ticks 被动回 amount 蓝（meta 缺省 = 无此增益零开销；
## 重复拾取聚合 interval/amount 各自求和——间隔变长、单次量变大，附录 C 加法语义）。
func passive_energy_tick(_frame: int) -> void:
	var interval := int(get_meta("buff_passive_energy_interval_ticks", 0))
	if interval <= 0:
		_passive_energy_acc = 0
		return
	_passive_energy_acc += 1
	if _passive_energy_acc >= interval:
		_passive_energy_acc -= interval
		add_energy(int(get_meta("buff_passive_energy_amount", 0)))

## m2-t35 蓝能汲取：击杀 chance 概率回 amount 蓝（掷签走 RunState 独立盐流，可回放；
## chance ≤ 0 不消费 RNG。EventBus.enemy_killed 订阅在 _ready 建立）。
func _on_enemy_killed(_enemy_id: String) -> void:
	var chance := float(get_meta("buff_kill_energy_chance", 0.0))
	if chance <= 0.0:
		return
	if _kill_rng == null:
		_kill_rng = RunState.stream(SALT_KILL_ENERGY)
	if _kill_rng.randf() >= chance:
		return
	add_energy(int(get_meta("buff_kill_energy_amount", 0)))

## m2-t35 ③：buff 绝对写覆盖缝修补（裁定⑨「buff 重 apply 后补天赋 apply」的落地式）。
## BuffManager.apply_to_player/_to_rig 对六键为绝对写（只保留饮料 meta 贡献）：
## crit_pct / crit_dmg_pct / status_rate_pct / shield_delay_reduction_ticks / roll_cd_pct /
## element_proc_chance。每拍 buff 重 apply 后由接线点（run_root._start_floor /
## inter_floor._on_buff_chosen）调用本方法，把 TalentSystem.effects_of 里六键的天赋
## 贡献补回。成对语义（wipe→repair）保证不叠加；开场首拍走 talents.apply_to_player
## （own-delta 已含六键），不走本方法（否则翻倍）。其余可加键（hp/盾/能/移速/攻速/
## 弹速）buff 侧 own-delta 天然保留天赋贡献，无需修补。
func repair_talent_absolute_keys() -> void:
	crit_bonus += talent_effect_value("crit_pct")
	crit_damage_bonus += talent_effect_value("crit_dmg_pct")
	status_rate_bonus += talent_effect_value("status_rate_pct")
	shield_delay_reduction_ticks += int(talent_effect_value("shield_delay_reduction_ticks"))
	roll_cd_pct += talent_effect_value("roll_cd_pct")
	if weapon_rig != null:
		weapon_rig.enchant_proc_chance += talent_effect_value("element_proc_chance")

func effective_move_speed(frame: int) -> float:
	var boost := move_speed_boost_pct if frame < move_speed_boost_until else 0.0
	var slow := incoming_slow_pct if frame < incoming_slow_until else 0.0
	return move_speed * (1.0 + boost) * maxf(0.0, 1.0 - slow)

func effective_crit_chance(base: float) -> float:
	return clampf(base + crit_bonus, 0.0, 1.0)

func effective_crit_multiplier() -> float:
	return maxf(1.0, 2.0 + crit_damage_bonus)

func effective_status_rate_multiplier() -> float:
	return maxf(0.0, 1.0 + status_rate_bonus)

func is_invincible_at(frame: int) -> bool:
	return frame < _iframe_until or frame < _roll_end_frame

func is_invincible() -> bool:
	return is_invincible_at(Engine.get_physics_frames())

## 技能接缝（m1-t5 影袭）：开启一段无敌窗，取 max 不缩短既有窗（含受伤/翻滚窗）。
func apply_iframes(ticks: int, frame: int) -> void:
	_iframe_until = maxi(_iframe_until, frame + ticks)

func take_hit(ctx: Dictionary) -> void:
	take_hit_ctx(ctx, Engine.get_physics_frames())

func take_hit_ctx(ctx: Dictionary, frame: int) -> void:
	# 非正伤害必须在狂潮减伤、状态、无敌帧和护盾结算前成为完整 no-op；
	# 否则狂潮的 min 1 会把负数变成伤害，shield - dmg 也会反向增加护盾。
	var dmg := maxi(0, int(ctx.get("amount", 0)))
	if dmg == 0:
		return
	# m4-c3 抗毒（anti_poison，0/1 flag）：POISON 元素归因来伤免疫——玩家侧无独立
	# 「中毒」状态载体，POISON 归因来伤是唯一中毒向量（藤蔓巨像毒雨/星陨先知毒弹）。
	# 免疫=完整 no-op（不吃无敌帧不进护盾结算，同 dmg==0 口径；anti_ice 先例仅免减速，
	# 本键 desc「免疫中毒」无部分减免语义）。无增益（meta 缺省 0）逐字节零漂移。
	if int(ctx.get("element", Elements.Id.NONE)) == Elements.Id.POISON \
			and int(get_meta("buff_anti_poison", 0)) == 1:
		return
	if is_invincible_at(frame):
		# m2-t33 成就补线（K.3 走位大师窗口源）：翻滚无敌帧内躲过「弹幕」计数
		# （仅 source_type "projectile"；接触/状态伤害与受击无敌帧不属「躲弹幕」口径）。
		if frame < _roll_end_frame and String(ctx.get("source_type", "")) == "projectile":
			AchievementSystem.notify_roll_dodge()
		return
	# m2-t35 甲壳：弹幕伤害 ×(1+buff_bullet_dmg_taken_pct)（负值 = 减免；向下取整且
	# 不低于 1，与狂潮/潮汐减伤同一 min 1 口径）。只对弹幕（source_type "projectile"）生效。
	if String(ctx.get("source_type", "")) == "projectile":
		var bullet_pct := float(get_meta("buff_bullet_dmg_taken_pct", 0.0))
		if bullet_pct != 0.0:
			dmg = maxi(1, int(floor(float(dmg) * (1.0 + bullet_pct))))
	var slow_ticks := int(ctx.get("slow_ticks", 0))
	var slow_pct := clampf(float(ctx.get("slow_pct", 0.0)), 0.0, 1.0)
	# m2-t35 抗冰：冰系（element ICE）附带减速免疫；非冰系减速（藤蔓/孢子等）照常生效。
	if slow_ticks > 0 and slow_pct > 0.0 \
			and not (int(get_meta("buff_anti_ice", 0)) == 1
				and int(ctx.get("element", Elements.Id.NONE)) == Elements.Id.ICE):
		incoming_slow_pct = maxf(incoming_slow_pct if frame < incoming_slow_until else 0.0, slow_pct)
		incoming_slow_until = maxi(incoming_slow_until, frame + slow_ticks)
	_iframe_until = frame + effective_hurt_iframe_ticks()
	_last_damaged_frame = frame
	_open_vengeance_window(frame)   # m4-c3：复仇者受击开窗（结算收尾前，先于减伤/护盾）
	if frame < rampage_active_until:
		dmg = maxi(1, int(floor(float(dmg) * RAMPAGE_DR)))   # 狂潮(升级)：-30%
	if frame < tide_guard_until:
		dmg = maxi(1, int(floor(float(dmg) * TIDE_DR)))      # 生命潮汐(升级)：法阵内 -20%
	var shield_before := shield
	var hp_before := hp
	var effective_before := maxi(0, shield_before) + maxi(0, hp_before)
	var to_hp := maxi(0, dmg - shield)
	shield = maxi(0, shield - dmg)
	if to_hp > 0:
		hp = maxi(0, hp - to_hp)
	# m2-t35 不死鸟：致死伤害保留 1 HP（附录 C「每局 1 次」）——消费记号独立于聚合 meta，
	# BuffManager 重 apply 绝对重写 flag=1 也不会第二次复活。
	if hp <= 0 and int(get_meta("buff_phoenix_flag", 0)) == 1 \
			and int(get_meta(PHOENIX_USED_META, 0)) == 0:
		set_meta(PHOENIX_USED_META, 1)
		hp = 1
	# 事件、死亡回顾、遥测和表现均使用真实落地伤害。来伤可以超过剩余
	# 护盾+生命，但 overkill 不能虚高本次受击或死亡窗口中的数值。
	var actual := mini(maxi(0, dmg), effective_before)
	_shield_next_at = frame + maxi(0, SHIELD_DELAY_TICKS - shield_delay_reduction_ticks)
	if shield_before > 0 and shield == 0:
		EventBus.shield_broken.emit()                        # 破碎拍广播（坚守被动在此挂钩）
	var fatal := hp <= 0
	# 不修改调用方共享 ctx；将实际结算伤害、帧和来源补齐后发详细归因信号。
	var resolved := ctx.duplicate(true)
	resolved["amount"] = actual
	resolved["fatal"] = fatal
	resolved["frame"] = frame
	resolved["source_type"] = String(ctx.get("source_type", ""))
	resolved["source_id"] = String(ctx.get("source_id", ""))
	resolved["source_name"] = String(ctx.get("source_name", ""))
	resolved["attack_name"] = String(ctx.get("attack_name", ""))
	resolved["from"] = ctx.get("from", global_position)
	resolved["remaining_hp"] = hp
	resolved["roll_available"] = roll_ready_at(frame)
	resolved["hp_damage"] = mini(hp_before, to_hp)
	EventBus.player_hit_resolved.emit(actual, fatal, resolved)
	EventBus.player_damaged.emit(actual, fatal)   # 旧两参契约仍只发一次
	Telemetry.log_row(["hurt", frame, actual, hp])   # m1-t18：hurt 行收口至玩家受击路径（原 training_room 本地行）
	Fx.on_player_hurt(self, actual, ctx.get("from", global_position))   # from → J6 方向指示（D-3b）
	_reflect_thorns(ctx)                             # m2-t35：荆棘护甲接触反伤（命中结算后）

## m2-t35 荆棘护甲：被接触（source_type "contact"）时对来敌反伤 thorns_contact_dmg。
## m2-t35 评审 Minor⑤（T33 顺手修）：目标 = 真正「就近」来敌——M0 "enemies" 分组内
## 16px 环中距 ctx.from（接触瞬间方位）最近者（原实现取组序首个，与方位无关）。
## 致死接触照常反伤（附录 C「被接触时反伤 3」无致死例外；结算位于受击收尾，测试钉死）。
func _reflect_thorns(ctx: Dictionary) -> void:
	if String(ctx.get("source_type", "")) != "contact":
		return
	var thorns := int(get_meta("buff_thorns_contact_dmg", 0))
	if thorns <= 0 or not is_inside_tree():
		return
	var from: Vector2 = ctx.get("from", global_position)
	var nearest: Node2D = null
	var nearest_d := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node2D
		if e == null:
			continue
		var bp: Variant = e.get("brain_pos")
		var e_pos: Vector2 = bp if typeof(bp) == TYPE_VECTOR2 else e.global_position
		var d := e_pos.distance_to(from)
		if d <= 16.0 and d < nearest_d:
			nearest = e
			nearest_d = d
	if nearest != null:
		nearest.take_hit({
			"amount": thorns, "is_crit": false, "element": Elements.Id.NONE,
			"from": global_position, "source_type": "thorns",
			"source_id": "thorn_armor", "source_name": "荆棘护甲", "attack_name": "荆棘反伤",
			"player_damage": true,
		})

## 被动「坚守」（GDD §6 骑士·凛）：护盾破碎瞬间对 60px 内敌人 1 伤 + 击退 8px + 眩晕 30t。
## 寻敌沿用 M0 分组（RoomCombat 刷怪即入 "enemies" 组），位置以 brain_pos 权威（同敌方 AI）。
func _on_shield_broken() -> void:
	if not has_defiance or not is_inside_tree():
		return
	var frame := Engine.get_physics_frames()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		var to := e.brain_pos - global_position
		if to.length() > DEFIANCE_RADIUS_PX:
			continue
		e.take_hit({"amount": 1, "is_crit": false, "element": Elements.Id.NONE, "from": global_position})
		if e.state == EnemyBase.State.DEAD:                  # 被 1 伤终结则不再位移/眩晕尸体
			continue
		e.brain_pos += to.normalized() * DEFIANCE_KNOCKBACK_PX
		e.stun_until = frame + DEFIANCE_STUN_TICKS

func _shield_tick(frame: int) -> void:
	if shield >= shield_max or frame < _shield_next_at:
		return
	shield += 1
	_shield_next_at = frame + SHIELD_INTERVAL_TICKS

func shield_at(frame: int) -> int:
	# 纯查询：给定未来帧的护盾值（测试与 UI 预估用）
	if shield >= shield_max or frame < _shield_next_at:
		return shield
	var gained := int(floor(float(frame - _shield_next_at) / SHIELD_INTERVAL_TICKS)) + 1
	return mini(shield_max, shield + gained)

## 治疗单一收口（m2-t26 评审 I-1）：挑战房 heal_disable 灾厄以临时 meta 挂在玩家上
## （FloorScene 进房挂载/房清或场景销毁摘除），一切治疗源（红心拾取、喷泉、商店、
## 技能如守护者生命潮汐）统一经此处拦截——红心掉落截断在 FloorScene._spawn_pickup，
## 技能/设施侧不再各自判灾厄。返回是否实际回复（测试断言用；所有调用方均可忽略）。
func heal(n: int) -> bool:
	if has_meta(CALAMITY_HEAL_DISABLED_META):
		return false
	hp = mini(hp_max, hp + n)
	return true

func add_energy(n: int) -> void:
	energy = mini(energy_max, energy + n)

func combat_radius() -> float:
	return 6.0

func combat_faction() -> int:
	return Projectile.Faction.PLAYER
