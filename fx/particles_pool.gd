class_name ParticlesPool
extends Node
## M3 J-C（Juice v2 §2 J3/J4）：池化条带播放器——命中火花 / 枪口焰 / 击杀碎片环 / J7 白闪。
##
## 方案取舍（任务卡二选一，取 Sprite2D + AtlasTexture 帧步进）：
## - 池级单 _process 集中驱动 N 单元；AnimatedSprite2D 每单元自带内部计时与
##   animation_finished，200+ 节点各自处理且无法集中降级（关帧动画）；
## - AtlasTexture.region 原地改写零分配；headless 测试可注入 step(dt) 手动推进，时序确定。
##
## 预算与降级（规格 §2 J3「同屏 ≤200；超预算自动降级——关帧动画退化为单帧贴图」）：
## - BUDGET=200：活跃请求时 ≥200 → 进入降级模式（后续请求单帧：只显示第 0 帧），
##   活跃数回落至预算内自动恢复（规格给出的「X 秒/至活跃回落」二选一取后者，确定性）；
## - POOL_SIZE=240 > BUDGET：降级语义是「不换图」而非「不显示」，200~239 区间降级请求
##   仍出图（单帧），≥240 池硬容量兜底直接丢弃；
## - 表现参数（预算/降级阈值/帧时长/tint 预设色/1.3×）以模块常量承载（对齐 AudioMgr
##   POOL_SIZE=8 先例），规格出处见各行注释；收口时是否入 balance.json 由 J-D 裁定。
##
## 热路径零分配：play_* 只做标量赋值与既有对象字段改写；字典查找仅在请求时刻一次
##（不逐帧），帧步进为纯标量比较。闭包/字典仅出现在事件驱动路径（Boss 死亡白闪）。
## 最近邻过滤 + 整数帧宽（480×270 像素风红线；暴击 1.3× 为规格明示例外）。

const POOL_SIZE := 240                    # 池硬容量（启动建满、常驻 visible=false 回收）
const BUDGET := 200                       # 同屏帧动画预算（Juice v2 §2 J3 / GDD §18.3）
const FRAME_TIME := 0.05                  # 20 帧/s：spark 0.2s / muzzle 0.15s / shard 0.3s
const CRIT_SCALE := 1.3                   # 规格 §2 J3：暴击 1.3×（唯一明示缩放例外）
const CRIT_TINT := Color(1.0, 0.85, 0.2)  # 金（对齐 Fx 暴击数字金）

const STRIP_SPARK_HIT := "spark_hit"
const STRIP_SPARK_CRIT := "spark_crit"
const STRIP_SPARK_FIRE := "spark_fire"
const STRIP_SPARK_ICE := "spark_ice"
const STRIP_SPARK_POISON := "spark_poison"
const STRIP_SPARK_SHOCK := "spark_shock"
const STRIP_MUZZLE := "muzzle_v2"
const STRIP_KILL_SHARD := "kill_shard"

## 枪口焰按武器类别 tint（规格 §2 J3：步枪/霰弹/激光三组预设色；表外类别不 tint）。
## 色值为实现预设（步枪热白黄/霰弹橙/激光青），收口归 J-D 裁定。
const MUZZLE_TINTS := {
	"rifle": Color(1.0, 0.95, 0.6),
	"shotgun": Color(1.0, 0.62, 0.25),
	"laser": Color(0.55, 0.9, 1.0),
}

## J7 Boss 死亡白闪：复用 BossBase._phase_flash 手法（独立 CanvasLayer +
## PROCESS_MODE_ALWAYS + ignore_time_scale 定时回收，0.25s 同阶段闪常量）。
const DEATH_FLASH_SECONDS := 0.25
const DEATH_FLASH_ALPHA := 0.82
const DEATH_FLASH_LAYER_NAME := "BossDeathFlash"

## 播放单元：常驻 Sprite2D，字段全预分配（play 路径只写字段，零分配）。
class Unit extends Sprite2D:
	var strip := ""            # 当前条带 id（测试断言用；空闲为 ""）
	var frames := 0            # 条带帧数
	var fidx := 0              # 当前帧号（自有字段，不用 Sprite2D.frame/hframes 语义）
	var t := 0.0               # 已播时长
	var duration := 0.0
	var degraded := false      # 降级单帧：锁第 0 帧不逐帧换图
	var playing := false

var _pool: Array[Unit] = []          # 启动建满，运行期不增减
var _active_count := 0
var _degrade := false
## m4-k3：存在非 WHITE 光圈折叠色的活跃单元（光圈消失后的回落复位依据；复位完成
## 即清零回到常态零成本早退）。
var _aid_tinted := false
## 条带注册表（启动时从 ArtLookup 构建一次；tex 为 null → 该条带 fail-closed 跳过）。
var _strips: Dictionary = {}         # id -> {tex: Texture2D, frames: int}


func _ready() -> void:
	_build_pool()
	var tree := get_tree()
	if tree != null:
		# J7 必跟①：boss_base.gd 不改——经 node_added 全局挂钩订阅所有 BossBase 实例
		# 的 boss_defeated（实例信号无静态形态，EventBus 亦无对应频道）。
		tree.node_added.connect(_on_node_added)


func _build_pool() -> void:
	for strip_id: String in ArtLookup.FX_STRIPS:
		_strips[strip_id] = {
			"tex": ArtLookup.tex(ArtLookup.fx_strip_path(strip_id)),
			"frames": ArtLookup.fx_strip_frames(strip_id),
		}
	for i in POOL_SIZE:
		var u := Unit.new()
		u.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 480×270 像素风红线
		u.z_index = 40                                          # 与 Fx._puff 同层
		u.visible = false
		var at := AtlasTexture.new()                            # 启动期分配（允许）
		u.texture = at
		add_child(u)
		_pool.append(u)


## node_added 挂钩：新入树 BossBase 逐实例订阅死亡信号（连接随实例释放自动清理）。
func _on_node_added(node: Node) -> void:
	if node is BossBase:
		(node as BossBase).boss_defeated.connect(_on_boss_defeated)


## J7 必跟①：Boss 死亡表现——kill_shard 碎片环 + 全屏白闪（恰一次由 BossBase.die
## 状态门保证）。脑测 Boss 不在树内 → 零表现不崩。
func _on_boss_defeated(boss: BossBase) -> void:
	if not boss.is_inside_tree():
		return
	play_kill_shard(boss.global_position)
	_spawn_death_flash()


func _spawn_death_flash() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var layer := CanvasLayer.new()                  # 事件驱动路径：允许分配
	layer.name = DEATH_FLASH_LAYER_NAME
	layer.layer = 1000
	layer.process_mode = Node.PROCESS_MODE_ALWAYS   # 定格冻结期间白闪仍可见
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 1.0, 1.0, DEATH_FLASH_ALPHA)
	layer.add_child(rect)
	tree.root.add_child(layer)
	tree.create_timer(DEATH_FLASH_SECONDS, true, false, true).timeout.connect(
		func() -> void:
			if is_instance_valid(layer):
				layer.queue_free())


# ---- 播放 API（全部标量参数：逐命中热路径零分配，不用 opts 字典） ----

## 通用播放：strip_id 播于 pos；scale/tint/rot 可选（默认 1×/原色/朝右 0°）。
func play(strip_id: String, pos: Vector2, scale := 1.0, tint := Color.WHITE, rot := 0.0) -> void:
	var s: Dictionary = _strips.get(strip_id, {})
	if s.is_empty() or (s["tex"] as Texture2D) == null:
		return                              # 注册缺失/缺图：fail-closed 静默（表由测试守护）
	if _active_count >= BUDGET:
		_degrade = true                     # 规格：活跃 ≥ 预算 → 降级标记（单帧模式）
	var u := _take_free_unit()
	if u == null:
		return                              # 池硬容量兜底：超额请求丢弃
	var tex := s["tex"] as Texture2D
	var frame_count := int(s["frames"])
	var frame_w := tex.get_width() / maxi(frame_count, 1)
	u.strip = strip_id
	u.frames = frame_count
	u.fidx = 0
	u.t = 0.0
	u.duration = FRAME_TIME * frame_count
	u.degraded = _degrade
	u.position = pos
	u.rotation = rot
	u.scale = Vector2(scale, scale)
	u.modulate = tint
	# m4-k3（K-3 披露收口）：A2 光圈内粒子增亮折叠（BiomeFx.bullet_aid 同形，状态源/
	# 半径/强度走既有口径）。粒子不进光照参与集（T37 探针 +47 draw 已否决）——表现侧
	# self_modulate 写入零批处理成本、零判定影响；与 modulate tint 相乘互不覆盖。
	# 无光圈 = WHITE（frame-0 正确 + 池化复用复位安全）。随 bullet_aid 先例不发遥测。
	u.self_modulate = BiomeFx.light_aid_at(pos)
	if u.self_modulate != Color.WHITE:
		_aid_tinted = true
	u.visible = true
	u.playing = true
	_active_count += 1
	_set_frame(u, tex, frame_w, 0)


## 命中火花三态（J3）：暴击 → spark_crit（金 tint + 1.3×）；四元素 → 对应条带；否则通用。
func play_spark(pos: Vector2, is_crit: bool, element: int) -> void:
	if is_crit:
		play(STRIP_SPARK_CRIT, pos, CRIT_SCALE, CRIT_TINT)
		return
	match element:
		Elements.Id.FIRE:
			play(STRIP_SPARK_FIRE, pos)
		Elements.Id.ICE:
			play(STRIP_SPARK_ICE, pos)
		Elements.Id.POISON:
			play(STRIP_SPARK_POISON, pos)
		Elements.Id.SHOCK:
			play(STRIP_SPARK_SHOCK, pos)
		_:
			play(STRIP_SPARK_HIT, pos)


## 枪口焰（J3）：三帧条带，按武器类别 tint，朝向即弹道角（条带素材朝右 0°）。
func play_muzzle(pos: Vector2, angle: float, weapon_category: String) -> void:
	play(STRIP_MUZZLE, pos, 1.0, MUZZLE_TINTS.get(weapon_category, Color.WHITE) as Color, angle)


## 击杀/ Boss 死亡碎片环（J3/J7）：v1 爆散（Fx._puff）之上叠加的 6 帧环。
func play_kill_shard(pos: Vector2) -> void:
	play(STRIP_KILL_SHARD, pos)


# ---- 帧驱动（生产：_process 逐帧；测试：step(dt) 注入，时序确定） ----

func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if _degrade and _active_count < BUDGET:
		_degrade = false                    # 活跃回落至预算内 → 恢复帧动画
	if _active_count == 0:
		return                              # 热路径早退
	# m4-k3：折叠色逐帧刷新（跟随玩家/光圈位移与 _vision_factor 缩径）；光圈消失后
	# 复位 WHITE 并清零 _aid_tinted（回落完成即回常态零成本）。仅活跃单元写入。
	var aid := BiomeFx.light_aid_active() or _aid_tinted
	var tinted := false
	for u in _pool:
		if not u.playing:
			continue
		if aid:
			u.self_modulate = BiomeFx.light_aid_at(u.global_position)
			if u.self_modulate != Color.WHITE:
				tinted = true
		u.t += delta
		if u.t >= u.duration:
			_recycle(u)
			continue
		if u.degraded:
			continue                        # 降级：锁第 0 帧，不做逐帧换图
		var f := mini(int(u.t / FRAME_TIME), u.frames - 1)
		if f != u.fidx:
			var s: Dictionary = _strips.get(u.strip, {})
			var tex := s.get("tex") as Texture2D
			if tex != null:
				_set_frame(u, tex, tex.get_width() / maxi(u.frames, 1), f)
	_aid_tinted = tinted


func _set_frame(u: Unit, tex: Texture2D, frame_w: int, f: int) -> void:
	u.fidx = f
	(u.texture as AtlasTexture).atlas = tex
	(u.texture as AtlasTexture).region = Rect2(f * frame_w, 0.0, frame_w, float(tex.get_height()))


func _take_free_unit() -> Unit:
	for u in _pool:
		if not u.playing:
			return u
	return null


func _recycle(u: Unit) -> void:
	u.playing = false
	u.visible = false
	u.strip = ""
	u.degraded = false
	u.self_modulate = Color.WHITE        # m4-k3：回收复位（池化跨层不泄漏；play 侧亦覆写）
	_active_count -= 1


# ---- 查询（测试/遥测用；生产热路径不调用） ----

func active_units() -> int:
	return _active_count


func capacity() -> int:
	return POOL_SIZE


func is_degraded() -> bool:
	return _degrade


func units() -> Array[Unit]:
	return _pool
