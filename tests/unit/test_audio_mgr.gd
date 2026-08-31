class_name TestAudioMgr
extends GdUnitTestSuite
## m2-t5 音频管理器：sfx 池 8 语音轮转 / 未知 key 警告一次 / 流缓存复用 /
## 音量 clamp 与持久化。Audio playback 本身无法在 headless 断言——按控制器决议
## 只断言 player 状态（playing / stream / pitch / volume_db）。
## 涉及持久化的用例走全新实例 + 临时路径 SaveSystem（save_path 注入），
## 不触碰真实 user://save.json（同 test_save.gd 既定模式）。


## 警告间谍：记录 push_warning 次数（同 test_save.gd SpySaver 惯例）。
class SpyWarn extends "res://autoload/audio_mgr.gd":
	var warnings: Array[String] = []

	func _warn(msg: String) -> void:
		warnings.append(msg)

	func warning_count() -> int:
		return warnings.size()


const AUDIO_MGR_SCRIPT := preload("res://autoload/audio_mgr.gd")
const MUTE_DB := -80.0

var _tmp_paths: Array[String] = []


func after_test() -> void:
	for path in _tmp_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_tmp_paths.clear()


## 全新 AudioMgr 实例（in-tree → _ready 建池 + 读音量）；host 为设置宿主注入。
func _fresh(host: Node = null) -> Node:
	var mgr: Node = auto_free(AUDIO_MGR_SCRIPT.new())
	mgr.set("settings_host", host)
	add_child(mgr)
	return mgr


func _spy() -> Node:
	var mgr: Node = auto_free(SpyWarn.new())
	add_child(mgr)
	return mgr


## 临时路径 SaveSystem 替身（不触发真实存档读写）。
func _tmp_settings() -> Node:
	var s: Node = auto_free(load("res://autoload/save_system.gd").new())
	var path := "user://test_audio_%d.json" % absi(randi())
	s.set("save_path", path)
	_tmp_paths.append(path)
	s.call("load_save")
	return s


func _players(mgr: Node) -> Array:
	var out := []
	for c in mgr.get_children():
		# m2-t22：排除 music 通道（名为 "Music" 的常驻单实例），本文件只测 sfx 池。
		if c is AudioStreamPlayer and c.name != "Music":
			out.append(c)
	return out


func test_autoload_registered_after_save_system() -> void:
	# 只读冒烟：AudioMgr 注册在 SaveSystem 之后（project.godot 顺序契约）
	var mgr: Node = get_tree().root.get_node_or_null("AudioMgr")
	assert_that(mgr).is_not_null()
	assert_int(get_tree().root.get_children().find(mgr)) \
		.is_greater(get_tree().root.get_children().find(get_tree().root.get_node("SaveSystem")))
	assert_int(_players(mgr).size()).is_equal(8)


func test_pool_round_robin_reuses_all_eight_and_steals_oldest() -> void:
	var mgr := _fresh()
	var players := _players(mgr)
	assert_int(players.size()).is_equal(8)
	for i in 8:
		mgr.play("ui_click")
	# 8 次播放后 8 个 player 全部被用过（stream 已挂载）。
	# 注：不断言瞬态 playing（0.09s 音效在全量负载下可能已自然播完），
	# 轮转契约由 pitch 持久值钉住（play 后 pitch_scale 常驻）。
	for p in players:
		assert_that((p as AudioStreamPlayer).stream).is_not_null()
	assert_float((players[7] as AudioStreamPlayer).pitch_scale).is_equal(1.0)
	# 第 9 次播放：无空闲语音 → 轮转回最旧（players[0]，被夺走，pitch 覆写为 1.5）
	mgr.play("ui_click", 1.5)
	assert_float((players[0] as AudioStreamPlayer).pitch_scale).is_equal(1.5)


func test_unknown_key_warns_once_and_is_silent_noop() -> void:
	var mgr := _spy()
	mgr.play("laser_blast")           # 不在 KEYS
	mgr.play("laser_blast")           # 同 key 只警告一次
	assert_int(mgr.warning_count()).is_equal(1)
	for p in _players(mgr):
		assert_that((p as AudioStreamPlayer).stream).is_null()   # 不崩、无声


func test_missing_wav_warns_once_and_noops() -> void:
	# 已知 key 但 WAV 缺失（如未来包体裁剪）：同样警告一次 + 静默 no-op
	var mgr := _spy()
	mgr.set("sfx_dir", "res://audio/generated/sfx/does_not_exist/")
	mgr.play("crit_hit")
	mgr.play("crit_hit")
	mgr.play("crit_hit")
	assert_int(mgr.warning_count()).is_equal(1)
	for p in _players(mgr):
		assert_that((p as AudioStreamPlayer).stream).is_null()


func test_stream_cache_reuses_same_instance() -> void:
	var mgr := _fresh()
	mgr.play("hit_enemy")
	mgr.play("hit_enemy")
	var players := _players(mgr)
	var s0: AudioStream = (players[0] as AudioStreamPlayer).stream
	var s1: AudioStream = (players[1] as AudioStreamPlayer).stream
	assert_bool(s0 == s1).is_true()   # 同一 stream 实例（load 缓存复用）


func test_play_applies_pitch_scale() -> void:
	var mgr := _fresh()
	var players := _players(mgr)
	mgr.play("hit_enemy")
	assert_float((players[0] as AudioStreamPlayer).pitch_scale).is_equal(1.0)
	mgr.play("crit_hit", 1.15)
	assert_float((players[1] as AudioStreamPlayer).pitch_scale).is_equal_approx(1.15, 0.0001)


func test_set_sfx_volume_clamps_and_applies_to_pool() -> void:
	var mgr := _fresh(_tmp_settings())
	mgr.set_sfx_volume(1.7)           # 上越界 → 1.0（= 0 dB）
	assert_float(mgr.get_sfx_volume()).is_equal(1.0)
	for p in _players(mgr):
		assert_float((p as AudioStreamPlayer).volume_db).is_equal_approx(0.0, 0.001)
	mgr.set_sfx_volume(-0.5)          # 下越界 → 0.0（静音 = -80 dB）
	assert_float(mgr.get_sfx_volume()).is_equal(0.0)
	for p in _players(mgr):
		assert_float((p as AudioStreamPlayer).volume_db).is_equal(MUTE_DB)
	mgr.set_sfx_volume(0.5)           # 线性 0.5 → linear_to_db
	assert_float(mgr.get_sfx_volume()).is_equal(0.5)
	for p in _players(mgr):
		assert_float((p as AudioStreamPlayer).volume_db).is_equal_approx(linear_to_db(0.5), 0.001)


func test_sfx_volume_persisted_to_settings_and_disk() -> void:
	var host := _tmp_settings()
	var mgr := _fresh(host)
	mgr.set_sfx_volume(0.25)
	# 活动设置读回（AudioMgr._ready 同源）
	assert_float(float(host.get_setting("sfx_volume", 1.0))).is_equal(0.25)
	# 落盘（set_setting → save_now 原子写）
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.get("save_path")))
	assert_that(parsed).is_not_null()
	assert_float(float((parsed as Dictionary)["settings"]["sfx_volume"])).is_equal(0.25)


func test_ready_reads_persisted_volume() -> void:
	var host := _tmp_settings()
	host.set_setting("sfx_volume", 0.25)   # 预置已保存音量
	var mgr := _fresh(host)                # add_child 触发 _ready → 读取
	assert_float(mgr.get_sfx_volume()).is_equal(0.25)
	for p in _players(mgr):
		assert_float((p as AudioStreamPlayer).volume_db).is_equal_approx(linear_to_db(0.25), 0.001)


func test_death_key_maps_to_enemy_die_wav() -> void:
	# 规格字面键 "death" 经 KEY_FILE 映射到 enemy_die.wav（评审 Major①）：
	# 可播出 + 同实例缓存复用 + 资源确为 enemy_die
	var mgr := _fresh()
	mgr.play("death")
	mgr.play("death")
	var players := _players(mgr)
	var s0: AudioStream = (players[0] as AudioStreamPlayer).stream
	var s1: AudioStream = (players[1] as AudioStreamPlayer).stream
	assert_that(s0).is_not_null()
	assert_bool(s0 == s1).is_true()   # 同 key 缓存复用（load 缓存同实例）
	assert_bool(s0 == load("res://audio/generated/sfx/enemy_die.wav")).is_true()


func test_set_music_volume_clamps_and_roundtrips() -> void:
	var mgr := _fresh(_tmp_settings())
	mgr.set_music_volume(0.4)
	assert_float(mgr.get_music_volume()).is_equal(0.4)
	mgr.set_music_volume(2.0)             # 上越界 → 1.0
	assert_float(mgr.get_music_volume()).is_equal(1.0)
	mgr.set_music_volume(-0.5)            # 下越界 → 0.0
	assert_float(mgr.get_music_volume()).is_equal(0.0)
	mgr.set_music_volume(0.0)             # music 音量不得泄漏到 sfx 池（通道本体 T23）
	for p in _players(mgr):
		assert_float((p as AudioStreamPlayer).volume_db).is_equal_approx(0.0, 0.001)


func test_music_volume_persisted_to_settings_and_disk() -> void:
	var host := _tmp_settings()
	var mgr := _fresh(host)
	mgr.set_music_volume(0.3)
	# 活动设置读回（AudioMgr._ready 同源）
	assert_float(float(host.get_setting("music_volume", 1.0))).is_equal(0.3)
	# 落盘（set_setting → save_now 原子写）
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.get("save_path")))
	assert_that(parsed).is_not_null()
	assert_float(float((parsed as Dictionary)["settings"]["music_volume"])).is_equal(0.3)


func test_ready_reads_persisted_music_volume() -> void:
	var host := _tmp_settings()
	host.set_setting("music_volume", 0.35)   # 预置已保存音量
	var mgr := _fresh(host)                   # add_child 触发 _ready → 读取
	assert_float(mgr.get_music_volume()).is_equal(0.35)
