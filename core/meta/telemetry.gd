extends Node
## 遥测（m0-t12 建，m1-t18 集中化重写）：内存缓冲 + 定期落盘（每 32 行或每 60 物理帧）。
## m0 为 class_name 静态类逐行 open+seek+flush 写 user://telemetry.csv（高频 hit/fire 行逐行过盘）；
## m1-t18 改注册 autoload "Telemetry"（移除 class_name，全局名单例）——全部调用点
## `Telemetry.log_row(...)` 经 autoload 全局名解析保持不改（披露：静态类 → 单例，语义等价）。
## 列契约：event,ts_frame,v1,v2,v3,source（m1-t18 追加 source 列；kill 行由房间发射点
## 显式传入 boss 标记 / 玩家武器 id，缺省 ""）。会话计数 kills/hurt_count/rooms
## 供 T22 死亡结算经 session_summary() 读取。

const PATH := "user://telemetry.csv"
const HEADER := "event,ts_frame,v1,v2,v3,source"
const FLUSH_ROWS := 32     # 行数阈值：缓冲满即落盘
const FLUSH_FRAMES := 60   # 帧数阈值：60 物理帧（1s）内必有一次落盘
const FPS := 60.0

var _buf: Array[String] = []
var _frames_since_flush := 0
var _kills := 0
var _hurt_count := 0
var _rooms := 0
var _start_frame := 0

func _ready() -> void:
	_start_frame = Engine.get_physics_frames()

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
	if _buf.size() >= FLUSH_ROWS:
		flush()

## 落盘（文件首建写表头；追加语义同 m0）。磁盘不可写 → fail-soft 丢批告警不致崩。
func flush() -> void:
	_frames_since_flush = 0
	if _buf.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(PATH, FileAccess.WRITE)
		if f == null:
			push_warning("Telemetry: cannot open %s — dropping %d rows" % [PATH, _buf.size()])
			_buf.clear()
			return
		f.store_line(HEADER)
	f.seek_end()
	for line in _buf:
		f.store_line(line)
	f.flush()
	_buf.clear()

## 本局汇总（T22 死亡结算读取）；run_time 为自会话起点（autoload 就绪 / reset_session）起的秒数。
func session_summary() -> Dictionary:
	return {
		"kills": _kills,
		"hurt_count": _hurt_count,
		"rooms": _rooms,
		"run_time": float(Engine.get_physics_frames() - _start_frame) / FPS,
	}

## 新局清零（T22 重开结算口径）。
func reset_session() -> void:
	_kills = 0
	_hurt_count = 0
	_rooms = 0
	_start_frame = Engine.get_physics_frames()

func _count_row(event: String) -> void:
	match event:
		"kill":
			_kills += 1
		"hurt":
			_hurt_count += 1
		"room_clear", "floor_clear":
			_rooms += 1
