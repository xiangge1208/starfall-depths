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
##   _ready 读回）；music 通道本体（2 通道/总线布局）留给 T23，本卡不施加到任何节点。

const POOL_SIZE := 8
const DEFAULT_VOLUME := 1.0
const MUTE_DB := -80.0                    # 0 线性音量对应的 dB（替代 -inf）
const SFX_DIR_DEFAULT := "res://audio/generated/sfx/"

## 已知音效 key（spec 固定表；player_hurt/door_open/ui_click 本卡已有 WAV）。
## "death" 为 spec 字面键，实际音源为 enemy_die.wav（经 KEY_FILE 映射，评审 Major①）。
const KEYS := [
	"shoot_player", "shoot_enemy", "melee_swing", "hit_enemy", "crit_hit",
	"pickup_coin", "pickup_energy", "pickup_heart", "player_hurt", "door_open", "ui_click",
	"death",
]

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
## music 通道线性音量快照（0..1，经 clamp）；通道本体 T23 建。
var music_volume := DEFAULT_VOLUME

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}             # key -> AudioStream（含 null=缺失，缓存负结果）
var _warned: Dictionary = {}              # key -> true（每 key 至多警告一次）
var _next := 0                            # round-robin 游标

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_load_volume()
	_apply_volume()

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
	_settings().set_setting("music_volume", music_volume)   # 通道本体 T23；先落 API+持久化契约

func get_music_volume() -> float:
	return music_volume

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
