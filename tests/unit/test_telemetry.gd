class_name TestTelemetry
extends GdUnitTestSuite
## m0-t12：遥测 CSV 首建带表头、追加行。

func test_log_row_appends() -> void:
	DirAccess.remove_absolute("user://telemetry.csv")   # 不存在时报错可忽略
	Telemetry.log_row(["m0", 1, 2])
	assert_bool(FileAccess.file_exists("user://telemetry.csv")).is_true()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_str(text).contains("m0,1,2")
