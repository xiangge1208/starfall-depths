class_name TimeConst
const FPS := 60.0
static func ticks(seconds: float) -> int:
	return int(round(seconds * FPS))
