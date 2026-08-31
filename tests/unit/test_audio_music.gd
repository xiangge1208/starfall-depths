class_name TestAudioMusic
extends GdUnitTestSuite
## m2-t22 音乐通道（AudioMgr music 扩展）：play_music 幂等（同曲不重启）/
## 切曲 0.5s 淡入 / stop_music / boss_layer(true→boss 曲、false→恢复生态曲) /
## 未知 key 警告一次 / set_music_volume 施加到 music 通道（不泄漏 sfx 池）。
## 另覆盖 G-2 曲目资产契约：5 曲文件存在 + WAV 头合法（22050Hz/16bit/单声道）+
## 新曲 music_garden 时长 ≥110s + 全部曲目非静音（跨数据块抽样 decode_s16）。
## headless 无音频输出设备——与 test_audio_mgr.gd 同口径：只断言 player 状态
## （playing / stream / volume_db），不断言听感。
##
## 跨文件说明：tests/unit/test_audio_mgr.gd 的 _players() 帮助函数排除名为
## "Music" 的通道（本卡新增第 9 个 AudioStreamPlayer），其余不改。

## 警告间谍（同 test_audio_mgr.gd SpyWarn 惯例）。
class SpyWarn extends "res://autoload/audio_mgr.gd":
	var warnings: Array[String] = []

	func _warn(msg: String) -> void:
		warnings.append(msg)

	func warning_count() -> int:
		return warnings.size()


const AUDIO_MGR_SCRIPT := preload("res://autoload/audio_mgr.gd")
const MUSIC_DIR := "res://audio/generated/music/"
const MUTE_DB := -80.0
## GDD §17 五曲：菜单 1 + 生态 3（garden/crystal/magma）+ Boss 1。
## （music_battle.wav 为 T5 时期额外占位，不在 play_music 键表——披露。）
const MUSIC_KEYS := ["menu", "garden", "crystal", "magma", "boss"]


func after_test() -> void:
	# 接线冒烟用例动了全局 autoload 音乐通道：收尾恢复静默，不污染其它用例。
	var live := get_tree().root.get_node_or_null("AudioMgr")
	if live != null:
		live.stop_music()


func _fresh() -> Node:
	var mgr: Node = auto_free(AUDIO_MGR_SCRIPT.new())
	add_child(mgr)
	return mgr


func _spy() -> Node:
	var mgr: Node = auto_free(SpyWarn.new())
	add_child(mgr)
	return mgr


## music 通道节点（名为 "Music" 的 AudioStreamPlayer，区别于 8 语音 sfx 池）。
func _music_player(mgr: Node) -> AudioStreamPlayer:
	for c in mgr.get_children():
		if c is AudioStreamPlayer and c.name == "Music":
			return c
	return null


# ================================================================ 通道与 API

func test_music_channel_exists_alongside_sfx_pool() -> void:
	var mgr := _fresh()
	assert_that(_music_player(mgr)).is_not_null()
	var pool := 0
	for c in mgr.get_children():
		if c is AudioStreamPlayer and c.name != "Music":
			pool += 1
	assert_int(pool).is_equal(8)


func test_play_music_loads_stream_plays_and_fades_in() -> void:
	var mgr := _fresh()
	mgr.play_music("garden")
	var p := _music_player(mgr)
	assert_that(p.stream).is_not_null()
	assert_bool(p.stream == load(MUSIC_DIR + "music_garden.wav")).is_true()
	assert_bool(p.playing).is_true()
	assert_float(p.volume_db).is_equal(MUTE_DB)   # 淡入起点（0.5s → 目标音量）
	await get_tree().create_timer(0.85).timeout   # 淡入完成（0.5s + 余量）
	assert_float(p.volume_db).is_equal_approx(0.0, 0.5)   # 默认 music_volume=1 → 0 dB


func test_play_music_idempotent_same_key_does_not_restart() -> void:
	var mgr := _fresh()
	mgr.play_music("garden")
	await get_tree().create_timer(0.25).timeout   # 淡入中段
	var p := _music_player(mgr)
	var mid_db := p.volume_db
	assert_bool(mid_db > MUTE_DB + 5.0).is_true()   # 已在淡入（非起点）
	mgr.play_music("garden")                       # 同曲二次调用：必须不重启
	assert_bool(p.playing).is_true()
	assert_bool(p.volume_db > mid_db - 5.0).is_true()   # 音量未被打回 MUTE_DB（=重启痕迹）
	assert_bool(p.stream == load(MUSIC_DIR + "music_garden.wav")).is_true()


func test_play_music_switch_key_restarts_fade_with_new_stream() -> void:
	var mgr := _fresh()
	mgr.play_music("garden")
	await get_tree().create_timer(0.85).timeout
	var p := _music_player(mgr)
	mgr.play_music("crystal")   # 切曲：换 stream + 音量回 MUTE_DB 重新淡入
	assert_bool(p.stream == load(MUSIC_DIR + "music_crystal.wav")).is_true()
	assert_float(p.volume_db).is_equal(MUTE_DB)
	await get_tree().create_timer(0.85).timeout
	assert_float(p.volume_db).is_equal_approx(0.0, 0.5)


func test_unknown_music_key_warns_once_and_is_silent_noop() -> void:
	var mgr := _spy()
	mgr.play_music("dubstep")
	mgr.play_music("dubstep")     # 同 key 只警告一次
	assert_int(mgr.warning_count()).is_equal(1)
	var p := _music_player(mgr)
	assert_that(p.stream).is_null()
	assert_bool(p.playing).is_false()


func test_stop_music_resets_channel() -> void:
	var mgr := _fresh()
	mgr.play_music("menu")
	var p := _music_player(mgr)
	assert_bool(p.playing).is_true()
	mgr.stop_music()
	assert_bool(p.playing).is_false()
	assert_that(p.stream).is_null()
	mgr.stop_music()              # 幂等：再停不崩


func test_set_music_volume_applies_to_music_channel_not_sfx_pool() -> void:
	var mgr := _fresh()
	mgr.set_music_volume(0.5)
	assert_float(_music_player(mgr).volume_db).is_equal_approx(linear_to_db(0.5), 0.001)
	mgr.set_music_volume(0.0)     # 0 线性 → MUTE_DB（映射同 sfx 池约定）
	assert_float(_music_player(mgr).volume_db).is_equal(MUTE_DB)
	for c in mgr.get_children():
		if c is AudioStreamPlayer and c.name != "Music":
			assert_float((c as AudioStreamPlayer).volume_db).is_equal_approx(0.0, 0.001)


# ================================================================ Boss 动态切层

func test_boss_layer_on_switches_to_boss_and_off_restores_biome() -> void:
	var mgr := _fresh()
	mgr.play_music("garden")
	mgr.boss_layer(true)
	var p := _music_player(mgr)
	assert_str(mgr.get("_music_key")).is_equal("boss")
	assert_bool(p.stream == load(MUSIC_DIR + "music_boss.wav")).is_true()
	mgr.boss_layer(true)          # 已在 boss 层：幂等不重启
	assert_str(mgr.get("_music_key")).is_equal("boss")
	mgr.boss_layer(false)         # 退场 → 恢复进 boss 前的生态曲
	assert_str(mgr.get("_music_key")).is_equal("garden")
	assert_bool(p.stream == load(MUSIC_DIR + "music_garden.wav")).is_true()
	mgr.boss_layer(false)         # 已不在 boss 层：no-op
	assert_str(mgr.get("_music_key")).is_equal("garden")
	assert_bool(p.playing).is_true()


func test_boss_layer_on_off_from_silence_stops_cleanly() -> void:
	var mgr := _fresh()
	mgr.boss_layer(false)         # 无 boss 曲可退：no-op 不崩
	var p := _music_player(mgr)
	assert_bool(p.playing).is_false()
	mgr.boss_layer(true)          # 静默进 boss 层：直接 boss 曲
	assert_str(mgr.get("_music_key")).is_equal("boss")
	assert_bool(p.playing).is_true()
	mgr.boss_layer(false)         # 无生态曲可恢复（boss_layer(true) 前无音乐）→ 停
	assert_bool(p.playing).is_false()


# ================================================================ 接线（1-2 行冒烟）

func test_floor_scene_boss_room_event_raises_boss_layer() -> void:
	# Boss 房进入钩子：FloorScene._on_flow_room_event("boss") → AudioMgr.boss_layer(true)
	var floor_scene: Node = auto_free(load("res://core/rooms/floor_scene.gd").new())
	add_child(floor_scene)
	var live := get_tree().root.get_node("AudioMgr")
	live.play_music("crystal")
	floor_scene._on_flow_room_event("boss", 3)
	assert_str(live.get("_music_key")).is_equal("boss")
	live.boss_layer(false)        # 退回生态曲（模拟 boss_defeated 分支语义）
	assert_str(live.get("_music_key")).is_equal("crystal")


# ================================================================ 曲目资产契约

## 解析 WAV 头（RIFF chunk 走查）：返回 channels/sample_rate/bits/data 起点+字节数。
func _parse_wav(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_that(f).is_not_null()
	if f == null:
		return {}
	var riff := f.get_buffer(4).get_string_from_ascii()
	assert_bool(riff == "RIFF").is_true()
	f.seek(12)                    # 跳过 RIFF size + "WAVE"
	var fmt := {}
	var data_off := -1
	var data_bytes := 0
	while f.get_position() + 8 <= f.get_length():
		var chunk_id := f.get_buffer(4).get_string_from_ascii()
		var chunk_size := f.get_32()
		if chunk_id == "fmt ":
			fmt["audio_format"] = f.get_16()
			fmt["channels"] = f.get_16()
			fmt["sample_rate"] = f.get_32()
			f.seek(f.get_position() + 6)          # byte_rate(4) + block_align(2)
			fmt["bits"] = f.get_16()
			if chunk_size > 16:
				f.seek(f.get_position() + chunk_size - 16)
		elif chunk_id == "data":
			data_off = f.get_position()
			data_bytes = chunk_size
			f.seek(f.get_position() + chunk_size + (chunk_size & 1))
		else:
			f.seek(f.get_position() + chunk_size + (chunk_size & 1))
	fmt["data_off"] = data_off
	fmt["data_bytes"] = data_bytes
	return fmt


## 非静音：data 块内跨全程抽样（步长 ~50ms）decode_s16 峰值 > 阈值。
func _peak_of(path: String) -> int:
	var fmt := _parse_wav(path)
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(int(fmt["data_off"]))
	var buf := f.get_buffer(int(fmt["data_bytes"]))
	var peak := 0
	var step := 1102              # ~50ms @22050Hz（16bit 单声道）
	for i in range(0, buf.size() - 1, step):
		peak = maxi(peak, absi(buf.decode_s16(i)))
	return peak


func test_five_music_tracks_exist_and_are_valid_wav() -> void:
	for key: String in MUSIC_KEYS:
		var path := MUSIC_DIR + "music_" + key + ".wav"
		assert_bool(FileAccess.file_exists(path)).is_true()
		var fmt := _parse_wav(path)
		assert_int(int(fmt.get("channels", 0))).is_equal(1)
		assert_int(int(fmt.get("bits", 0))).is_equal(16)
		assert_int(int(fmt.get("sample_rate", 0))).is_equal(22050)


func test_new_garden_track_is_loop_length_120s() -> void:
	# 本卡新生成的 A1 生态曲须达 GDD 2 分钟规格（≥110s 门限）。
	# 注：menu/crystal/magma/boss 四曲为 T5 时期既有占位（规格「已存在则跳过」），
	# 时长 9.6~19.2s，不作 ≥110s 断言（披露；--force 可全量重生成 2 分钟版）。
	var fmt := _parse_wav(MUSIC_DIR + "music_garden.wav")
	var duration := float(int(fmt["data_bytes"])) / 2.0 / 22050.0   # 16bit 单声道
	assert_float(duration).is_greater_equal(110.0)


func test_all_music_tracks_are_not_silent() -> void:
	for key: String in MUSIC_KEYS:
		assert_int(_peak_of(MUSIC_DIR + "music_" + key + ".wav")).is_greater(1000)
