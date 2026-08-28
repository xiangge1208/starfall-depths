class_name Telemetry
## 遥测（m0-t12）：CSV 追加写 user://telemetry.csv，首建写表头。
## 列契约：event,ts_frame,v1,v2,v3（埋点：fire/hit/kill/hurt/room_clear）。

const PATH := "user://telemetry.csv"
const HEADER := "event,ts_frame,v1,v2,v3"

static func log_row(cols: Array) -> void:
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(PATH, FileAccess.WRITE)
		f.store_line(HEADER)
	f.seek_end()
	f.store_line(",".join(cols.map(func(c): return str(c))))
	f.flush()
