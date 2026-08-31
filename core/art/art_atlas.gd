class_name ArtAtlas
extends RefCounted
## m2-t37 全图集查询（纯静态、可单测）：art/generated/atlas/atlas.json + 单页图
## → 按路径的 AtlasTexture 区域。GDD §18.3「draw call ≤150（全图集）」前提落地——
## 所有经 ArtLookup.tex 的世界精灵共享同一页纹理（批处理合并的前提）。
##
## 契约（与 tools/gen_art_atlas.py 产物对齐；test_art_atlas 逐项断言）：
## - 清单键 = art/generated 相对路径（与 ArtLookup 表驱动 relpath 同一口径）；
## - 区域整数像素（最近邻采样不模糊不渗色，padding 外扩由生成器负责）；
## - fail-closed：清单/页缺失、路径不在表、区域越界 → 返回 null，调用方回落
##   ArtLookup 原逐文件纹理路径（游戏表现零依赖图集存在）；
## - tiles/* 与 *_sheet.png 不入图集（repeat 平铺 / hframes 帧表依赖独立整图）。

const MANIFEST_PATH := "res://art/generated/atlas/atlas.json"
const PAGE_DIR := "res://art/generated/atlas/"
## 候选路径前缀：仅 art/generated 表驱动路径参与图集寻址。
const BASE_PREFIX := "res://art/generated/"

static var _enabled := true          # 测试/降级开关（false = 原逐文件路径直通）
static var _loaded := false          # 清单已加载（含加载失败的负缓存）
static var _manifest: Dictionary = {}        # rel -> Rect2i
static var _page: Texture2D = null
static var _page_size := Vector2i.ZERO
static var _regions: Dictionary = {}         # rel -> AtlasTexture（备忘，热路径零重建）


## 查询路径的图集区域（不在图集/未启用 → Rect2()）。单测与批处理断言消费。
static func region_of(path: String) -> Rect2i:
	if not _enabled or not path.begins_with(BASE_PREFIX):
		return Rect2i()
	_ensure_loaded()
	var rel := path.substr(BASE_PREFIX.length())
	var r: Rect2i = _manifest.get(rel, Rect2i())
	return r


## 查询路径的共享页 AtlasTexture；任何未命中（停用/无清单/无页/不在表/越界）
## 返回 null，由调用方回落逐文件纹理。
static func texture_for(path: String) -> Texture2D:
	var r := region_of(path)
	if r == Rect2i():
		return null
	var rel := path.substr(BASE_PREFIX.length())
	if _regions.has(rel):
		return _regions[rel]
	var page := page_texture()
	if page == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = page
	at.region = Rect2(r)
	var size_err := r.position.x < 0 or r.position.y < 0 \
		or r.end.x > _page_size.x or r.end.y > _page_size.y
	if size_err:
		push_warning("ArtAtlas: region out of page '%s' %s" % [path, r])
		return null
	_regions[rel] = at
	return at


## 共享图集页纹理实例（批处理契约：所有世界精灵同一底层纹理；test_art_atlas 断言）。
static func page_texture() -> Texture2D:
	_ensure_loaded()
	return _page


## 图集是否处于生效状态（清单加载成功且有页）。
static func is_active() -> bool:
	_ensure_loaded()
	return _enabled and _page != null


## 测试/降级开关：false 时 texture_for 直通 null（原逐文件路径）。
static func set_enabled(v: bool) -> void:
	if _enabled == v:
		return
	_enabled = v
	_regions.clear()                     # 切换作废全部 AtlasTexture 备忘


## 测试复位：清空全部缓存态，下次查询重载清单。
static func reset_for_tests() -> void:
	_enabled = true
	_loaded = false
	_manifest = {}
	_page = null
	_page_size = Vector2i.ZERO
	_regions = {}


# ---- 内部 ------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return                            # 图集未生成（fail-closed：静默回落，无告警刷屏）
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed == null or not (parsed is Dictionary):
		push_warning("ArtAtlas: manifest unparsable '%s'" % MANIFEST_PATH)
		return
	var data := parsed as Dictionary
	var page_name := String(data.get("page", ""))
	var size: Array = data.get("size", [])
	if page_name.is_empty() or size.size() != 2:
		push_warning("ArtAtlas: manifest missing page/size '%s'" % MANIFEST_PATH)
		return
	var page := load(PAGE_DIR + page_name) as Texture2D
	if page == null:
		push_warning("ArtAtlas: page texture missing '%s'" % page_name)
		return
	_page = page
	_page_size = Vector2i(int(size[0]), int(size[1]))
	var entries: Dictionary = data.get("entries", {}) as Dictionary
	# JSON.parse_string 产出 float——统一 int() 归一（工程既有 _normalize_row 惯例）
	for rel: String in entries:
		var rect: Array = entries[rel]
		if rect.size() != 4:
			push_warning("ArtAtlas: bad entry '%s' (expect [x,y,w,h])" % rel)
			continue
		_manifest[rel] = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
