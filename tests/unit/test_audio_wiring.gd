class_name TestAudioWiring
extends GdUnitTestSuite
## m4p-w2a 音频全面接线完备性（沿 test_art_wiring 手法把「WAV 在盘、代码零引用」
## 走查探针改写为正式回归）：
## ① 每个 sfx WAV 文件要么映射到 KEYS 键（同名或经 KEY_FILE 差异表），要么在
##    SFX_WAV_EXEMPT 豁免表（当前为空）；music 目录同理对 MUSIC_KEYS/MUSIC_WAV_EXEMPT
##    （唯一豁免 = music_battle.wav，T5 占位文件，披露）。
## ② 每个 KEYS 键全库（autoload/core/ui）≥1 个 play 调用点——静态 grep 口径：
##    - 常规键：源码含 `AudioMgr.play("<key>"` / `AudioMgr.play_once("<key>"` 字面；
##    - 前缀族键（pickup_*）：pickup.gd 的 `AudioMgr.play("pickup_" + kind)` 动态拼键；
##    - 武器分类键（shoot_player + 8 分类）：weapon_rig.CATEGORY_SHOOT_KEY 表驱动；
##    - ui_click：AudioMgr 自身的 node_added 全钮挂钩（play.bind("ui_click")）。
## ③ 既有 9 音源不回归：原始 (key → 调用点文件) 逐一钉死。
## 另有 play_once 同拍限流与 ui_click 全钮挂钩的行为冒烟（真实池断言，同 test_audio_mgr）。


const AUDIO_MGR_SCRIPT := preload("res://autoload/audio_mgr.gd")
const SCAN_DIRS: Array[String] = ["res://autoload", "res://core", "res://ui"]
const AUDIO_MGR_PATH := "res://autoload/audio_mgr.gd"
const WEAPON_RIG_PATH := "res://core/player/weapon_rig.gd"
const PICKUP_PATH := "res://core/rooms/pickup.gd"

## 动态拼键族：key → 载体文件（拼键前缀 + 文件内必须出现的拼键表达式）。
const DYNAMIC_FAMILY := {
	"pickup_coin": "res://core/rooms/pickup.gd",
	"pickup_energy": "res://core/rooms/pickup.gd",
	"pickup_heart": "res://core/rooms/pickup.gd",
	"pickup_gem": "res://core/rooms/pickup.gd",
}
const DYNAMIC_EXPR := 'AudioMgr.play("pickup_" + kind)'
## 表驱动族：weapon_rig.CATEGORY_SHOOT_KEY（表外 category 回落 shoot_player）。
const CATEGORY_KEYS: Array[String] = [
	"shoot_player", "shoot_bow", "shoot_laser", "shoot_rifle", "shoot_shotgun",
	"shoot_smg", "shoot_sniper", "shoot_staff", "shoot_throw",
]
const CATEGORY_EXPR := "AudioMgr.play_once(String(CATEGORY_SHOOT_KEY.get("
## AudioMgr 内部接线键（node_added 全钮挂钩；调用点在 audio_mgr.gd 自身）。
const INTERNAL_KEYS: Array[String] = ["ui_click"]
const INTERNAL_EXPR := 'play.bind("ui_click"'

## ③ 既有 9 音源（m2-t5 基线，卡验收「原样绿」）：key → 唯一发射点文件。
const LEGACY_SOURCES := {
	"crit_hit": "res://core/combat/combat_system.gd",
	"hit_enemy": "res://core/combat/combat_system.gd",
	"death": "res://core/enemies/enemy_base.gd",
	"melee_swing": "res://core/player/melee.gd",
	"shoot_player": "res://core/player/weapon_rig.gd",
	"shoot_enemy": "res://core/enemies/enemy_base.gd",
	"pickup_coin": "res://core/rooms/pickup.gd",
	"pickup_energy": "res://core/rooms/pickup.gd",
	"pickup_heart": "res://core/rooms/pickup.gd",
}


## const 表探针（不入树实例：_ready 不跑、不建池不触存档；仅读 KEYS/KEY_FILE/豁免表）。
var _probe: Node = null


func before_test() -> void:
	_probe = AUDIO_MGR_SCRIPT.new()


func after_test() -> void:
	if _probe != null:
		_probe.free()
		_probe = null


# ---------------------------------------------------------------- 源码扫描缝

## 去注释读源（行内 # 及之后内容剔除——KEYS 表注释里的 "gem" 字面不得计入）。
func _source(path: String) -> String:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var out: Array[String] = []
	for line: String in lines:
		var idx := line.find("#")
		out.append(line if idx < 0 else line.substr(0, idx))
	return "\n".join(out)


## 递归收集目录下全部 .gd 源（SCAN_DIRS 本就不含 tests/）。
func _gd_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = SCAN_DIRS.duplicate()
	while not stack.is_empty():
		var base: String = stack.pop_back()
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for f: String in dir.get_files():
			if f.ends_with(".gd"):
				out.append(base + "/" + f)
		for d: String in dir.get_directories():
			if not d.begins_with("."):
				stack.append(base + "/" + d)
	return out


func _keys() -> Array:
	return _probe.get("KEYS") as Array


# ---------------------------------------------------------------- ① WAV → 键完备

func test_every_sfx_wav_maps_to_key_or_exempt() -> void:
	var dir := DirAccess.open("res://audio/generated/sfx")
	assert_object(dir).is_not_null()
	var known: Array = (_keys() as Array) \
		+ (_probe.get("KEY_FILE") as Dictionary).values() \
		+ (_probe.get("SFX_WAV_EXEMPT") as Array)
	var wav_count := 0
	for f: String in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		wav_count += 1
		var base := f.get_basename()
		assert_bool(known.has(base)) \
			.override_failure_message("sfx wav '%s' 未映射 KEYS/KEY_FILE 亦未豁免" % f) \
			.is_true()
	assert_int(wav_count).is_greater(0)


func test_every_music_wav_maps_to_music_key_or_exempt() -> void:
	var dir := DirAccess.open("res://audio/generated/music")
	assert_object(dir).is_not_null()
	var music_keys: Array = _probe.get("MUSIC_KEYS") as Array
	var exempt: Array = _probe.get("MUSIC_WAV_EXEMPT") as Array
	var count := 0
	for f: String in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		count += 1
		var base := f.get_basename()
		var ok := music_keys.has(base.trim_prefix("music_")) or exempt.has(base)
		assert_bool(ok) \
			.override_failure_message("music wav '%s' 未映射 MUSIC_KEYS 亦未豁免" % f) \
			.is_true()
	assert_int(count).is_equal(6)
	# 披露口径：唯一豁免 = music_battle（T5 占位），且它不在正式曲表内
	assert_bool(exempt.has("music_battle")).is_true()
	assert_bool(music_keys.has("battle")).is_false()


# ---------------------------------------------------------------- ② 键 → play 调用点完备

func test_every_key_has_at_least_one_play_call_site() -> void:
	var sources := _gd_files()
	assert_int(sources.size()).is_greater(100)
	var stripped := {}                     # path -> 去注释源（读一遍，键循环复用）
	for f: String in sources:
		stripped[f] = _source(f)
	var mgr_src: String = stripped[AUDIO_MGR_PATH]
	var rig_src: String = stripped[WEAPON_RIG_PATH]
	var missing: Array[String] = []
	for key: String in _keys():
		var wired := false
		if DYNAMIC_FAMILY.has(key):
			wired = String(stripped[DYNAMIC_FAMILY[key]]).contains(DYNAMIC_EXPR)
		elif (CATEGORY_KEYS as Array).has(key):
			# 表驱动：字面键在 CATEGORY_SHOOT_KEY 表内 + play_once 消费缝存在
			wired = rig_src.contains('"%s"' % key) and rig_src.contains(CATEGORY_EXPR)
		elif (INTERNAL_KEYS as Array).has(key):
			wired = mgr_src.contains(INTERNAL_EXPR)
		else:
			var needle := 'AudioMgr.play("%s"' % key
			var needle_once := 'AudioMgr.play_once("%s"' % key
			for src: String in stripped.values():
				if src.contains(needle) or src.contains(needle_once):
					wired = true
					break
		if not wired:
			missing.append(key)
	assert_array(missing).override_failure_message(
		"以下 KEYS 键全库无 play 调用点: %s" % [missing]).is_empty()


# ---------------------------------------------------------------- ③ 既有 9 音源不回归

func test_legacy_nine_sources_keep_call_sites() -> void:
	for key: String in LEGACY_SOURCES:
		var src := _source(String(LEGACY_SOURCES[key]))
		var needle := 'AudioMgr.play("%s"' % key
		var ok := src.contains(needle) \
			or (key == "shoot_player" and _source(WEAPON_RIG_PATH).contains(CATEGORY_EXPR)) \
			or (DYNAMIC_FAMILY.has(key) and _source(PICKUP_PATH).contains(DYNAMIC_EXPR))
		assert_bool(ok) \
			.override_failure_message("既有音源 '%s' 在 %s 丢失调用点" % [key, LEGACY_SOURCES[key]]) \
			.is_true()
	# KEY_FILE 差异表不回归（death→enemy_die / pickup_gem→pickup_energy）
	var key_file: Dictionary = _probe.get("KEY_FILE")
	assert_str(String(key_file.get("death", ""))).is_equal("enemy_die")
	assert_str(String(key_file.get("pickup_gem", ""))).is_equal("pickup_energy")


func test_legacy_keys_survive_in_keys_table() -> void:
	for key: String in ["shoot_player", "shoot_enemy", "melee_swing", "hit_enemy",
			"crit_hit", "pickup_coin", "pickup_energy", "pickup_heart", "death"]:
		assert_bool((_keys() as Array).has(key)) \
			.override_failure_message("既有音源键 '%s' 被 KEYS 表扩展挤掉" % key).is_true()


# ---------------------------------------------------------------- 行为冒烟（真实池）

## 全新 AudioMgr（in-tree → _ready 建池）；同 test_audio_mgr._fresh 习语。
func _fresh() -> Node:
	var mgr: Node = auto_free(AUDIO_MGR_SCRIPT.new())
	add_child(mgr)
	return mgr


func _sfx_players(mgr: Node) -> Array:
	var out: Array = []
	for c in mgr.get_children():
		if c is AudioStreamPlayer and c.name != "Music":
			out.append(c)
	return out


func test_play_once_throttles_same_frame_duplicates() -> void:
	var mgr := _fresh()
	var next_before := int(mgr.get("_next"))
	mgr.play_once("roll")          # 新 key：本帧首播 → 推进游标
	var after_first := int(mgr.get("_next"))
	assert_int(after_first).is_equal(next_before + 1)
	mgr.play_once("roll")          # 同帧同 key → 限流跳过（一拍一音源一次）
	assert_int(int(mgr.get("_next"))).is_equal(after_first)
	mgr.play("roll")               # 裸 play 不受 play_once 节流影响（既有行为不回归）
	assert_int(int(mgr.get("_next"))).is_equal(after_first + 1)
	mgr.play_once("nova")          # 不同 key 各自独立限流槽
	assert_int(int(mgr.get("_next"))).is_equal(after_first + 2)


func test_ui_click_hook_plays_on_any_button_press() -> void:
	var mgr := _fresh()
	var btn := Button.new()
	add_child(btn)                 # node_added 挂钩即接线
	var players := _sfx_players(mgr)
	var with_stream := 0
	for p: AudioStreamPlayer in players:
		if p.stream != null:
			with_stream += 1
	btn.pressed.emit()             # 按下 → play("ui_click")
	var hit := 0
	for p: AudioStreamPlayer in players:
		if p.stream != null and (p.stream as AudioStream).resource_path.contains("ui_click"):
			hit += 1
	assert_int(hit).is_equal(1)    # 一钮一声（本实例池内恰占一语音）
	assert_int(with_stream).is_equal(0)   # 按下前池内无流（隔离断言）


func test_play_unknown_key_still_warn_once_no_crash() -> void:
	# 扩表后契约不回归：未知 key 警告一次 + 静默 no-op（同 test_audio_mgr 间谍口径轻量版）
	var mgr := _fresh()
	var next_before := int(mgr.get("_next"))
	mgr.play("no_such_key_w2a")
	assert_int(int(mgr.get("_next"))).is_equal(next_before)
