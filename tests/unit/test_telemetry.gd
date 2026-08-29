class_name TestTelemetry
extends GdUnitTestSuite
## m0-t12：遥测 CSV 首建带表头、追加行。
## m1-t18：集中化重写——内存缓冲（每 32 行或 60 物理帧落盘）、kill 行 source 列、
## 会话汇总 session_summary()（T22 用）、hurt 行收口至 Player.take_hit_ctx。

## 测试隔离：先把残留缓冲落盘，再删 CSV（下批行从干净的表头重建）。
func _clean() -> void:
	Telemetry.flush()
	DirAccess.remove_absolute("user://telemetry.csv")   # 不存在时报错可忽略

func test_log_row_appends() -> void:
	_clean()
	Telemetry.log_row(["m0", 1, 2])
	Telemetry.flush()
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_true()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_str(text).contains("m0,1,2")

# ---- m1-t18：缓冲落盘 ----

## 32 行阈值：缓冲满 32 行即自动落盘（此前不入盘）。
func test_flush_at_32_row_boundary() -> void:
	_clean()
	for i in 31:
		Telemetry.log_row(["t18", i, 0])
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_false()   # 31 行仍在缓冲
	Telemetry.log_row(["t18", 31, 0])                                        # 第 32 行触发
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_true()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_str(text).starts_with("event,ts_frame,v1,v2,v3,source")
	assert_int(text.split("\n", false).size()).is_equal(33)                  # 表头 + 32 行

## 60 物理帧阈值：不足 32 行也须在 60 物理帧内落盘（autoload _physics_process）。
func test_flush_every_60_physics_frames() -> void:
	_clean()
	Telemetry.log_row(["t60", 1])
	for _i in 30:
		await get_tree().physics_frame
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_false()   # 30 帧未到阈值
	for _i in 40:
		await get_tree().physics_frame                                       # 累计 70 ≥ 60
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_true()

# ---- m1-t18：kill 行 source 列 ----

func test_kill_row_carries_source_column() -> void:
	_clean()
	Telemetry.log_row(["kill", 100, "kuli_bug", 240], "laohuoji")
	Telemetry.flush()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_str(text).contains("kill,100,kuli_bug,240,laohuoji")

## 房间发射点来源判定（纯静态）：boss 行 → "boss"；否则玩家武器 id；未知 → ""。
func test_room_kill_source_helper() -> void:
	assert_str(RoomCombat.kill_source({"boss_script": "res://x.gd"}, "")).is_equal("boss")
	assert_str(RoomCombat.kill_source({"guest_kind": "boss"}, "laohuoji")).is_equal("boss")
	assert_str(RoomCombat.kill_source({}, "tiejian")).is_equal("tiejian")
	assert_str(RoomCombat.kill_source({}, "")).is_equal("")

# ---- m1-t18：会话汇总（T22 死亡结算用） ----

func test_session_summary_counts() -> void:
	Telemetry.reset_session()
	Telemetry.log_row(["kill", 1, "a", 10])
	Telemetry.log_row(["kill", 2, "b", 20])
	Telemetry.log_row(["hurt", 3, 2, 6])
	Telemetry.log_row(["room_clear", 4, 100])
	Telemetry.log_row(["floor_clear", 5, "tpl", 120])
	var summary := Telemetry.session_summary()
	assert_int(summary["kills"]).is_equal(2)
	assert_int(summary["hurt_count"]).is_equal(1)
	assert_int(summary["rooms"]).is_equal(2)        # room_clear + floor_clear
	assert_float(summary["run_time"]).is_greater_equal(0.0)

# ---- m1-t18：hurt 行收口至玩家受击路径（原 training_room 本地行删除） ----

func test_hurt_row_logged_from_player_take_hit_ctx() -> void:
	_clean()
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.take_hit_ctx({"amount": 3, "is_crit": false}, 100)   # 护盾 4 吸收：hp 仍 8
	Telemetry.flush()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_str(text).contains("hurt,100,3,8")
