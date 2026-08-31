extends Node
## 遥测（m0-t12 建，m1-t18 集中化重写）：内存缓冲 + 定期落盘（每 32 行或每 60 物理帧）。
## m0 为 class_name 静态类逐行 open+seek+flush 写 user://telemetry.csv（高频 hit/fire 行逐行过盘）；
## m1-t18 改注册 autoload "Telemetry"（移除 class_name，全局名单例）——全部调用点
## `Telemetry.log_row(...)` 经 autoload 全局名解析保持不改（披露：静态类 → 单例，语义等价）。
## 列契约：event,ts_frame,v1,v2,v3,source（m1-t18 追加 source 列；kill 行由房间发射点
## 显式传入 boss 标记 / 玩家武器 id，缺省 ""）。会话计数 kills/hurt_count/rooms
## 供 T22 死亡结算经 session_summary() 读取；floor_build 行另记基准帧供
## m2-t24 死亡回放键换算层内帧（floor_build_frame()）。

const PATH := "user://telemetry.csv"
const HEADER := "event,ts_frame,v1,v2,v3,source"
const FLUSH_ROWS := 32     # 行数阈值：缓冲满即落盘
const FLUSH_FRAMES := 60   # 帧数阈值：60 物理帧（1s）内必有一次落盘
const FPS := 60.0
const DPS_WINDOW_TICKS := 60

var _buf: Array[String] = []
var _frames_since_flush := 0
var _kills := 0
var _hurt_count := 0
var _rooms := 0
var _start_frame := 0
var _damage_window: Array[Dictionary] = []   # {frame, amount}；最近 60t 玩家实际伤害
var _damage_window_total := 0
var _peak_dps := 0
## m2-t24 死亡回放：最近一次 floor_build 行的全局帧（FloorScene.setup 落行）。
## 死亡回放键据此把致死全局帧换算为层内帧（death_frame = 致死帧 - 构建帧）；
## -1 = 本会话未见楼层构建（headless/异常注入路径）。
var _floor_build_frame := -1
## 文件系统接缝仅用于确定性模拟 Windows 瞬时打开失败；生产默认走 FileAccess。
## 注意：已有文件的 READ_WRITE 打开失败时绝不能降级为 WRITE，后者会截断历史。
var _file_exists_override: Callable = Callable()
var _file_open_override: Callable = Callable()

func _ready() -> void:
	_start_frame = Engine.get_physics_frames()
	EventBus.player_damage_resolved.connect(record_player_damage)

func _physics_process(_delta: float) -> void:
	_frames_since_flush += 1
	if _frames_since_flush >= FLUSH_FRAMES:
		flush()

## 兼容 m0 API：单参调用全部合法；source 缺省 ""。
func log_row(cols: Array, source: String = "") -> void:
	if cols.is_empty():
		return
	_buf.append(",".join(cols.map(func(c) -> String: return str(c))) + "," + source)
	_count_row(String(cols[0]))
	if String(cols[0]) == "floor_build" and cols.size() > 1:
		_floor_build_frame = int(cols[1])    # m2-t24：回放层内帧换算基准
	if _buf.size() >= FLUSH_ROWS:
		flush()


## 最近一次楼层构建的全局帧（-1 = 本会话未见 floor_build 行）。
func floor_build_frame() -> int:
	return _floor_build_frame

## 落盘（文件首建写表头；已有文件只按追加语义打开）。
## 磁盘暂时不可写 → fail-soft 保留内存批次，下一 flush 周期重试；绝不截断历史。
func flush() -> void:
	_frames_since_flush = 0
	if _buf.is_empty():
		return
	var existed := _file_exists(PATH)
	var mode := FileAccess.READ_WRITE if existed else FileAccess.WRITE
	var f := _open_file(PATH, mode)
	if f == null:
		push_warning("Telemetry: cannot open %s — retaining %d rows for retry" % [PATH, _buf.size()])
		return
	if not existed:
		f.store_line(HEADER)
	f.seek_end()
	for line in _buf:
		f.store_line(line)
	f.flush()
	_buf.clear()

func _file_exists(path: String) -> bool:
	if _file_exists_override.is_valid():
		return bool(_file_exists_override.call(path))
	return FileAccess.file_exists(path)

func _open_file(path: String, mode: FileAccess.ModeFlags) -> FileAccess:
	if _file_open_override.is_valid():
		return _file_open_override.call(path, mode) as FileAccess
	return FileAccess.open(path, mode)

## 本局汇总（T22 死亡结算读取）；run_time 为自会话起点（autoload 就绪 / reset_session）起的秒数。
func session_summary() -> Dictionary:
	return {
		"kills": _kills,
		"hurt_count": _hurt_count,
		"rooms": _rooms,
		"peak_dps": _peak_dps,
		"run_time": float(Engine.get_physics_frames() - _start_frame) / FPS,
	}

## 1 秒（60 逻辑帧）滚动伤害采样。frame 差 <60 属同一窗口；差恰为 60 已离窗。
## 仅生产侧 player_damage_resolved 进入本采样，敌人互伤/脚本辅助伤害不计玩家 DPS。
func record_player_damage(amount: int, frame: int) -> void:
	if amount <= 0:
		return
	_damage_window.append({"frame": frame, "amount": amount})
	_damage_window_total += amount
	while not _damage_window.is_empty() and frame - int(_damage_window[0]["frame"]) >= DPS_WINDOW_TICKS:
		_damage_window_total -= int(_damage_window[0]["amount"])
		_damage_window.remove_at(0)
	_peak_dps = maxi(_peak_dps, _damage_window_total)

## 新局清零（T22 重开结算口径）。
func reset_session() -> void:
	_kills = 0
	_hurt_count = 0
	_rooms = 0
	_damage_window.clear()
	_damage_window_total = 0
	_peak_dps = 0
	_floor_build_frame = -1
	_start_frame = Engine.get_physics_frames()

func _count_row(event: String) -> void:
	match event:
		"kill":
			_kills += 1
		"hurt":
			_hurt_count += 1
		"room_clear", "floor_clear":
			_rooms += 1
