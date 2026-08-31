extends Node
## 音频管理器 autoload（m2-t5）：sfx 池（8 语音，round-robin 复用）+ 全局接线 API。
## autoload 名 "AudioMgr"（无 class_name，命名规则同 SaveSystem/Fx），
## project.godot 中注册在 SaveSystem 之后。
##
## 设计（控制器决议）：
## - 语音全部走默认 Master 总线（keep simple；独立 SFX/Music 总线布局留给 M3 音量 UI 卡再议）。
## - play(key, pitch_scale)：key 不在 KEYS → push_warning 一次并返回（永不崩）；
##   已知 key 但 WAV 缺失（如未来包体裁剪）→ 同样警告一次 + 静默 no-op，
##   缺失结果随 stream 一起缓存（每 key 至多一次磁盘探测）。
## - WAV 经 load() 首次加载后缓存于 _streams（同 key 全池共享同一 stream 实例）。
## - 池策略：严格 round-robin——每次播放推进游标；8 语音全忙时第 9 次自然回到
##   最旧（游标序 = 最旧序），即「全忙夺最旧」语义，无需额外跟踪。
## - 音量：set_sfx_volume(0..1 线性) → clamp → linear_to_db 施加到全池，
##   并经 SaveSystem.set_setting("sfx_volume") 持久化；_ready 读回。
##   （0 线性映射 -80 dB 而非 -inf，避免 volume_db 出现无穷值。）
## - set_music_volume/get_music_volume 镜像 sfx 的持久化契约（clamp → set_setting，
##   _ready 读回）；m2-t22 起 music 通道本体（Music 单实例）就位，音量即施加。
##
## m2-t22 音乐通道（G-2 五曲 + Boss 动态切层）：
## - play_music(key)：music_<key>.wav 单实例播放；同 key 且播放中 → 幂等不重启；
##   切曲 = 换 stream + 音量回 MUTE_DB 0.5s 淡入（规格 crossfade 简化为 fade-in
##   ——单实例无第二通道，重叠淡出会与幂等门打架，disclose）。
## - boss_layer(on)：进 Boss 房切 boss 曲（记忆进层前生态曲），退场恢复；无曲可
##   恢复（进 boss 层前静默）→ 停。幂等：已在/不在 boss 层时重复调用 no-op。
## - 循环：运行时对 AudioStreamWAV 启用 LOOP_FORWARD 全长循环
##   （loop_end=帧数：PCM 按帧宽换算、QOA 用 get_length()*mix_rate；不依赖
##   .import 的 edit/loop_mode——生成的 WAV 无 smpl chunk 且导入器 compress/mode=2
##   默认 QOA，代码启用对正式替换素材同样生效）。
## - 未知 music key：同 sfx 约定 push_warning 一次 + 静默 no-op（_warned 以
##   "music:" 前缀与 sfx 键隔离）。

const POOL_SIZE := 8
const DEFAULT_VOLUME := 1.0
const MUTE_DB := -80.0                    # 0 线性音量对应的 dB（替代 -inf）
const SFX_DIR_DEFAULT := "res://audio/generated/sfx/"
const MUSIC_DIR := "res://audio/generated/music/"
const MUSIC_FADE_SEC := 0.5               # 切曲淡入时长（规格：0.5s crossfade 简化）

## 已知音效 key（spec 固定表；player_hurt/door_open/ui_click 本卡已有 WAV）。
## "death" 为 spec 字面键，实际音源为 enemy_die.wav（经 KEY_FILE 映射，评审 Major①）。
const KEYS := [
	"shoot_player", "shoot_enemy", "melee_swing", "hit_enemy", "crit_hit",
	"pickup_coin", "pickup_energy", "pickup_heart", "player_hurt", "door_open", "ui_click",
	"death",
]

## music key 表（GDD §17：菜单 1 + 生态 3 + Boss 1）。
## （music_battle.wav 为 T5 时期额外占位文件，不在本表——生态曲按层取 garden。）
const MUSIC_KEYS := ["menu", "garden", "crystal", "magma", "boss"]

## key → 文件基名差异表（未列出 = 与 key 同名 .wav）。仅在缓存 miss 路径查表，热路径零开销。
const KEY_FILE := {
	"death": "enemy_die",
}

## 设置宿主可注入（测试用临时路径 SaveSystem 替身）；null → 全局 SaveSystem。
var settings_host: Node = null
## 音源目录（测试注入坏目录覆盖「已知 key 但 WAV 缺失」路径；生产勿改）。
var sfx_dir := SFX_DIR_DEFAULT
## 当前线性音量快照（0..1，经 clamp）。
var sfx_volume := DEFAULT_VOLUME
## music 通道线性音量快照（0..1，经 clamp）；通道本体（Music 单实例）m2-t22 就位。
var music_volume := DEFAULT_VOLUME

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}             # key -> AudioStream（含 null=缺失，缓存负结果）
var _warned: Dictionary = {}              # key -> true（每 key 至多警告一次）
var _next := 0                            # round-robin 游标

var _music: AudioStreamPlayer = null      # music 通道（常驻单实例，节点名 "Music"）
var _music_key := ""                      # 当前曲 key（"" = 静默）
var _music_streams: Dictionary = {}       # music key -> AudioStream（含 null 负缓存）
var _music_tween: Tween = null            # 切曲淡入（同一时刻至多一个）
var _boss_base_key := ""                  # boss_layer(true) 时刻的生态曲（退场恢复用）

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"                 # sfx 池识别约定（测试 _players 排除名）
	add_child(_music)
	_load_volume()
	_apply_volume()
	_apply_music_volume()

func play(key: String, pitch_scale := 1.0) -> void:
	var stream := _stream_for(key)
	if stream == null:
		return
	var player := _pool[_next % POOL_SIZE]
	_next += 1
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.play()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_settings().set_setting("sfx_volume", sfx_volume)

func get_sfx_volume() -> float:
	return sfx_volume

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_music_volume()
	_settings().set_setting("music_volume", music_volume)

func get_music_volume() -> float:
	return music_volume


# ================================================================ m2-t22 音乐通道

## 播放 music_<key>.wav（单实例）：同曲播放中 → 幂等不重启；切曲 → 换 stream +
## 音量回 MUTE_DB 后 0.5s 淡入。未知 key / WAV 缺失 → 警告一次 + 静默 no-op。
func play_music(key: String) -> void:
	var stream := _music_stream_for(key)
	if stream == null:
		return
	if _music_key == key and _music.playing:
		return                              # 同曲幂等：不重启（淡入状态不回退）
	_music_key = key
	_enable_wav_loop(stream)
	_kill_music_tween()
	_music.stream = stream
	_music.volume_db = MUTE_DB
	_music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", _music_target_db(), MUSIC_FADE_SEC)

## 停止音乐并清空通道状态（幂等）。
func stop_music() -> void:
	_kill_music_tween()
	_music.stop()
	_music.stream = null
	_music_key = ""
	_boss_base_key = ""

## Boss 战动态切层（GDD §17）：on=切 boss 曲（记忆当前生态曲）；off=恢复生态曲，
## 无曲可恢复（进 boss 层前静默）则停。同状态重复调用幂等。
func boss_layer(on: bool) -> void:
	if on:
		if _music_key == "boss":
			return
		_boss_base_key = _music_key
		play_music("boss")
	else:
		if _music_key != "boss":
			return
		var restore := _boss_base_key
		_boss_base_key = ""
		if MUSIC_KEYS.has(restore) and restore != "boss":
			play_music(restore)
		else:
			stop_music()

func _music_stream_for(key: String) -> AudioStream:
	if not MUSIC_KEYS.has(key):
		_warn_once("music:" + key, "AudioMgr: unknown music key '%s'" % key)
		return null
	if _music_streams.has(key):
		return _music_streams[key] as AudioStream
	var path := MUSIC_DIR + "music_" + key + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		_warn_once("music:" + key, "AudioMgr: missing music wav '%s'" % path)
	_music_streams[key] = stream          # 负结果缓存（同 sfx 池约定）
	return stream

## 运行时启用 WAV 全长前向循环。幂等：重复调用无害。
## 帧数口径（loop_end 单位=帧，非字节）：
## - PCM（8/16bit）：data.size() / 帧宽（8bit=1、16bit=2；stereo ×2）。
## - QOA（导入器 compress/mode=2 默认，data.size() 为压缩字节数，不可当帧数）：
##   int(get_length() * mix_rate)（评审 Critical① 回归修复；无此分支则 QOA 曲
##   播一遍即停，无缝循环失效）。
## - 其它/未来格式：不启用（靠素材侧导入设置 edit/loop_mode）。
func _enable_wav_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS:
			var bytes_per_sample := 1 if wav.format == AudioStreamWAV.FORMAT_8_BITS else 2
			var bytes_per_frame := bytes_per_sample * (2 if wav.stereo else 1)
			if bytes_per_frame <= 0 or wav.data.size() < bytes_per_frame:
				return
			_set_full_loop(wav, wav.data.size() / bytes_per_frame)
		AudioStreamWAV.FORMAT_QOA:
			_set_full_loop(wav, int(wav.get_length() * wav.mix_rate))
		_:
			pass                              # 未知格式：静默不循环（同既定约定）

func _set_full_loop(wav: AudioStreamWAV, frames: int) -> void:
	if frames <= 0:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames

func _music_target_db() -> float:
	return MUTE_DB if music_volume <= 0.0 else linear_to_db(music_volume)

func _apply_music_volume() -> void:
	_kill_music_tween()
	if _music != null:
		_music.volume_db = _music_target_db()

func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null

func _load_volume() -> void:
	sfx_volume = clampf(float(_settings().get_setting("sfx_volume", DEFAULT_VOLUME)), 0.0, 1.0)
	music_volume = clampf(float(_settings().get_setting("music_volume", DEFAULT_VOLUME)), 0.0, 1.0)

func _apply_volume() -> void:
	var db := MUTE_DB if sfx_volume <= 0.0 else linear_to_db(sfx_volume)
	for p in _pool:
		p.volume_db = db

func _stream_for(key: String) -> AudioStream:
	if not KEYS.has(key):
		_warn_once(key, "AudioMgr: unknown sfx key '%s'" % key)
		return null
	if _streams.has(key):
		return _streams[key] as AudioStream
	var path := sfx_dir + String(KEY_FILE.get(key, key)) + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		_warn_once(key, "AudioMgr: missing sfx wav '%s'" % path)
	_streams[key] = stream   # 负结果也缓存：缺失 key 不重复探测/警告
	return stream

func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	_warn(msg)

## push_warning 缝隙（测试间谍覆写此方法计数，不打扰真实警告通道）。
func _warn(msg: String) -> void:
	push_warning(msg)

## 设置宿主解析：注入优先，否则全局 SaveSystem。
func _settings() -> Node:
	return settings_host if settings_host != null else SaveSystem
