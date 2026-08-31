extends CanvasLayer
## 右下角 toast 队列（m2-t32）：成就/解锁播报层，GDD §17「解锁即时提示，右下角
## toast 不打断战斗」。代码构建（无 tscn）：CanvasLayer + 纯 Label 行，无需场景装配。
##
## 队列口径：同屏最多 TOAST_MAX 3 条，超出立即挤掉最老一条（bounded 屏显）；
## 每条驻留 lifetime（3s 口径）末尾 FADE_SECS 淡出后释放并重排。
## lifetime 可注入（测试缩短/冻结）；headless 无树时 show_toast 静默忽略。

const TOAST_MAX := 3          # 同屏上限
const DURATION := 3.0         # 单条驻留口径（GDD/spec「3s 淡出」）
const FADE_SECS := 0.5        # 末段淡出时长（驻留 = hold + fade）
const LINE_HEIGHT := 30.0
const MARGIN := 16.0
const WIDTH := 340.0

## 驻留时长注入口（测试冻结/缩短）；<=0 时按 DURATION。
var lifetime: float = 0.0

var _lines: Array[Label] = []   # 同屏行（旧 → 新）


func _ready() -> void:
	layer = 100


## 入队一条 toast（duration 参数兼容扩展调用；-1 = 用 lifetime/DURATION 口径）。
func show_toast(text: String, duration: float = -1.0) -> void:
	var hold := duration if duration > 0.0 else (lifetime if lifetime > 0.0 else DURATION)
	var label := _build_label(text)
	add_child(label)
	_lines.append(label)
	while _lines.size() > TOAST_MAX:      # 同屏上限：挤掉最老一条（立即释放）
		var oldest: Label = _lines.pop_front()
		oldest.free()
	_relayout()
	if not is_inside_tree():
		return
	_expire_later(label, maxf(hold - FADE_SECS, 0.05))


func _expire_later(label: Label, hold: float) -> void:
	await get_tree().create_timer(hold).timeout
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, FADE_SECS)
	await tw.finished
	if is_instance_valid(label):
		_lines.erase(label)
		label.free()
		_relayout()


## 当前同屏文案（旧 → 新；测试断言口）。
func visible_texts() -> Array[String]:
	var out: Array[String] = []
	for l: Label in _lines:
		if is_instance_valid(l):
			out.append(l.text)
	return out


func _build_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(WIDTH, LINE_HEIGHT - 4.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.12, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	return label


## 右下角纵向堆叠（新行在最下），增删后重排。
func _relayout() -> void:
	if not is_inside_tree():
		return
	var vh := get_viewport().get_visible_rect().size.y
	for i in range(_lines.size()):
		var l: Label = _lines[i]
		if is_instance_valid(l):
			l.position = Vector2(get_viewport().get_visible_rect().size.x - WIDTH - MARGIN,
				vh - MARGIN - LINE_HEIGHT * float(_lines.size() - i))
