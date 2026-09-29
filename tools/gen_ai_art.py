#!/usr/bin/env python3
"""M5 美术升级：AI 生图管线（api.tu-zi.com，OpenAI Images 兼容接口）。

清单 tools/ai_art_manifest.json —— 42 项 = 选角立绘 20（ui/portrait_*.png 32x32，选角页
64px 显示）+ 设施/陈设贴图 22（tiles/ 12~20px）。取舍：只纳入游戏内实际渲染的单张独立
贴图（替换 = 换文件，零动画/图集/平铺风险）；排除角色/敌人帧表（多帧对齐）、地板/墙
（无缝平铺）、8~16px 图标/弹幕/拾取物（降采样即糊，程序化像素已达标）、logo_title /
icon_app（游戏内零引用：主菜单标题为 Label，应用图标为 icon.svg）。

流程（每步可单独重跑；--only a,b 过滤 id）：
  1 生成   python tools/gen_ai_art.py [--force]    -> art_ai/raw/<id>.png（默认 5 并发）
  2 验图   python tools/gen_ai_art.py --qa          -> art_ai/qa.json（对话模型视觉判定；
                                                        不合格 --only <ids> --force 重生成后再 --qa）
           python tools/gen_ai_art.py --sheets raw  -> art_ai/sheets/raw_*.png（人工复核拼板）
  3 降采样 python tools/gen_ai_art.py --process    -> art_ai/out/<id>.png
  4 对比   python tools/gen_ai_art.py --sheets cmp  -> art_ai/sheets/cmp_*.png（原图 | 新图）
  5 替换   python tools/gen_ai_art.py --apply      -> art/generated/（原件备份 art_ai/backup/）
    回滚   python tools/gen_ai_art.py --restore
密钥：环境变量 AI_ART_KEY 或仓库根 .ai_art_key（均 gitignore——仓库公开，密钥绝不入库）。
art_ai/ 带 .gdignore（Godot 不导入中间产物）。
"""
import argparse
import base64
import concurrent.futures
import http.client
import io
import json
import os
import shutil
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AI_DIR = os.path.join(ROOT, "art_ai")
RAW_DIR = os.path.join(AI_DIR, "raw")
OUT_DIR = os.path.join(AI_DIR, "out")
SHEET_DIR = os.path.join(AI_DIR, "sheets")
BACKUP_DIR = os.path.join(AI_DIR, "backup")
API = "https://api.tu-zi.com/v1/images/generations"
MODELS = ["gpt-image-2", "gpt-image-2.5"]   # 上游 5xx 时每 2 次尝试换下一模型
WORKERS = 5
ATTEMPTS = 6            # 请求级尝试（5xx / 网络耗尽）
CONNECT_RETRIES = 12    # 单次尝试内 TLS 握手/断连的快速重连（实测握手间歇失败）
TIMEOUT = 300
NET_ERRORS = (urllib.error.URLError, ssl.SSLError, ConnectionError,
              http.client.HTTPException, socket.timeout, TimeoutError)
OPTIONAL_PARAMS = ("background", "quality")   # 服务端不认时 400 自动剔除



def load_key() -> str:
    key = os.environ.get("AI_ART_KEY", "").strip()
    if not key:
        path = os.path.join(ROOT, ".ai_art_key")
        if os.path.exists(path):
            key = open(path, encoding="utf-8").read().strip()
    if not key:
        sys.exit("[gen_ai_art] no key: set AI_ART_KEY or write .ai_art_key")
    return key


def load_manifest() -> dict:
    with open(os.path.join(ROOT, "tools", "ai_art_manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def _urlopen(req, timeout: float) -> bytes:
    """网络层重连：TLS 握手/连接断开类错误快速重试（HTTPError 原样上抛交请求层）。"""
    last = None
    for n in range(CONNECT_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError:
            raise
        except NET_ERRORS as e:
            last = e
            time.sleep(min(2.0 + n, 8.0))
    raise ConnectionError(f"network exhausted after {CONNECT_RETRIES} reconnects: {last}")


SMALL_SPRITE_HINT = ("IMPORTANT: this is for a tiny {w}x{h} pixel game sprite. Draw it like a minimal "
    "classic 16-bit RPG item sprite: ONE simple bold shape, at most 4 flat colors, no gradients, no texture, no "
    "small details, thick black outline, very strong light-vs-dark contrast, the whole subject large and filling "
    "the frame. Absolutely no extra objects, no background props, no floor. ")
PORTRAIT_HINT = ("IMPORTANT: this is a tiny 32x32 pixel character portrait. Big simple head and shoulders filling "
    "the frame, large clear eyes, simple bold hair shape, at most 6 flat colors, no gradients, no fine texture, "
    "no floating particles, thick dark outline, strong contrast between face, hair and clothing. ")


def _size_hint(item: dict) -> str:
    w, h = item["size"]
    if item["id"].startswith("portrait_"):
        return PORTRAIT_HINT
    return SMALL_SPRITE_HINT.format(w=w, h=h) if max(w, h) <= 24 else ""


def gen_one(key: str, item: dict, style: str, model: str, drop: set) -> bytes:
    """生成单张，返回 PNG 字节。失败抛异常（HTTPError 或 ConnectionError）。"""
    body = {"model": model, "prompt": f"{style}. {_size_hint(item)}{item['prompt']}", "size": item["gen_size"],
            "n": 1, "response_format": "url"}
    if item.get("bg") == "transparent" and "background" not in drop:
        body["background"] = "transparent"
    if item.get("quality") and "quality" not in drop:
        body["quality"] = item["quality"]
    req = urllib.request.Request(API, data=json.dumps(body).encode("utf-8"), headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    payload = json.loads(_urlopen(req, TIMEOUT).decode("utf-8"))
    data = (payload.get("data") or [{}])[0]
    if data.get("b64_json"):
        return base64.b64decode(data["b64_json"])
    if data.get("url"):
        return _urlopen(urllib.request.Request(data["url"]), 120)
    raise RuntimeError(f"no image in response: {str(payload)[:160]}")


def gen_item(key: str, item: dict, style: str) -> tuple:
    drop: set = set()
    last = ""
    for attempt in range(1, ATTEMPTS + 1):
        model = MODELS[min((attempt - 1) // 2, len(MODELS) - 1)]
        try:
            png = gen_one(key, item, style, model, drop)
            from PIL import Image
            Image.open(io.BytesIO(png)).verify()          # 损坏/非图片即重试
            with open(os.path.join(RAW_DIR, f"{item['id']}.png"), "wb") as f:
                f.write(png)
            return item["id"], True, ""
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:200]
            bad = next((p for p in OPTIONAL_PARAMS if p in detail and p not in drop), None)
            if e.code == 400 and bad:
                drop.add(bad)                             # 服务端不认该参数 → 剔除后立即重试
                continue
            last = f"HTTP {e.code} {detail}"
            if 400 <= e.code < 500 and e.code != 429:
                break                                     # 4xx 非限流 = 请求本身问题，重试无意义
        except Exception as e:                            # noqa: BLE001
            last = f"{type(e).__name__}: {e}"
        print(f"  [{item['id']}] try {attempt} {model}: {last[:150]}", flush=True)
        time.sleep(10 * attempt)
    return item["id"], False, last


OUTLINE_RGB = (0x18, 0x14, 0x20)   # 调色板描边色（gen_placeholder_art OUTLINE；art_qa 底色同源）
WORK_PX = 256                      # 抠图/量化工作分辨率（目标 ≤32px，256 已远超所需）


def _components(mask) -> list:
    """4-连通分量（纯 Python BFS；只在 ≤64x64 的降采样 mask 上调用）。返回 [(area, bbox)]。"""
    h, w = mask.shape
    seen = [[False] * w for _ in range(h)]
    comps = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y][x]:
                continue
            stack, area = [(y, x)], 0
            seen[y][x] = True
            y0 = y1 = y
            x0 = x1 = x
            while stack:
                cy, cx = stack.pop()
                area += 1
                y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        stack.append((ny, nx))
            comps.append((area, (x0, y0, x1 + 1, y1 + 1)))
    return comps


def cutout(raw_path: str):
    """原图 → 工作尺度 (rgb uint8 HxWx3, mask bool HxW)。真透明通道直接用 alpha；否则
    （纯色底 / 伪透明棋盘格底）取边框主色集，flood-fill 抠掉与边框连通的近似底色区域
    （主体内部同色像素保留）。"""
    import numpy as np
    from PIL import Image, ImageDraw
    im = Image.open(raw_path).convert("RGBA")
    im.thumbnail((WORK_PX, WORK_PX), Image.LANCZOS)
    a = np.asarray(im).astype(np.int16)
    rgb, alpha = a[..., :3], a[..., 3]
    h, w = alpha.shape
    if (alpha < 16).mean() > 0.03:
        return rgb.astype(np.uint8), alpha >= 128
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    keys, inv, counts = np.unique(border // 16, axis=0, return_inverse=True, return_counts=True)
    inv = inv.ravel()
    refs, cum = [], 0
    for k in np.argsort(-counts)[:6]:
        refs.append(border[inv == k].mean(0))
        cum += counts[k]
        if cum >= 0.9 * len(border):
            break
    bglike = np.zeros((h, w), bool)
    for ref in refs:
        bglike |= np.abs(rgb - ref).max(-1) <= 18
    m = Image.fromarray(np.where(bglike, 255, 0).astype(np.uint8), "L")
    seeds = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    for pt in seeds:
        if m.getpixel(pt) == 255:
            ImageDraw.floodfill(m, pt, 128, thresh=0)
    return rgb.astype(np.uint8), np.asarray(m) != 128


def subject_bbox(mask):
    """主体框：4x 降采样后取面积 ≥3% 的连通分量并集（丢掉远离主体的星点/碎屑）。"""
    import numpy as np
    h, w = mask.shape
    f = 4
    small = mask[:h // f * f, :w // f * f].reshape(h // f, f, w // f, f).any(axis=(1, 3))
    comps = _components(small)
    if not comps:
        return None, mask
    total = sum(c[0] for c in comps)
    keep = [c for c in comps if c[0] >= max(2, 0.03 * total)]
    x0 = min(c[1][0] for c in keep) * f
    y0 = min(c[1][1] for c in keep) * f
    x1 = min(w, max(c[1][2] for c in keep) * f)
    y1 = min(h, max(c[1][3] for c in keep) * f)
    clean = np.zeros_like(mask)
    clean[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
    return (x0, y0, x1, y1), clean


def palette_downsample(rgb, mask, box, size, fit: str, colors: int):
    """裁主体 → 目标构图（portrait 取顶部正方；contain 底对齐补边）→ 增强 → 主体调色板
    量化 → 分块多数表决降采样（像素画平涂，不产生均值灰泥）。返回 (th, tw, 4) uint8。"""
    import numpy as np
    from PIL import Image, ImageEnhance
    x0, y0, x1, y1 = box
    sub, sm = rgb[y0:y1, x0:x1], mask[y0:y1, x0:x1]
    tw, th = size
    if fit == "portrait" and sub.shape[0] > sub.shape[1]:
        sub, sm = sub[:sub.shape[1]], sm[:sub.shape[1]]
    sh, sw = sm.shape
    if sw / sh > tw / th:
        pad = round(sw * th / tw) - sh
        sub, sm = np.pad(sub, ((pad, 0), (0, 0), (0, 0))), np.pad(sm, ((pad, 0), (0, 0)))
    else:
        pad = round(sh * tw / th) - sw
        pl = pad // 2
        sub = np.pad(sub, ((0, 0), (pl, pad - pl), (0, 0)))
        sm = np.pad(sm, ((0, 0), (pl, pad - pl)))
    img = ImageEnhance.Color(ImageEnhance.Contrast(Image.fromarray(sub)).enhance(1.15)).enhance(1.2)
    arr = np.asarray(img).astype(np.int32)
    pal_img = Image.fromarray(arr[sm].reshape(1, -1, 3).astype(np.uint8)).quantize(
        colors=colors, method=Image.Quantize.MEDIANCUT)
    pal = np.array(pal_img.getpalette()[:colors * 3], dtype=np.int32).reshape(-1, 3)
    idx = ((arr[..., None, :] - pal[None, None]) ** 2).sum(-1).argmin(-1)
    H, W = sm.shape
    ys = np.linspace(0, H, th + 1).round().astype(int)
    xs = np.linspace(0, W, tw + 1).round().astype(int)
    out = np.zeros((th, tw, 4), np.uint8)
    for j in range(th):
        for i in range(tw):
            bm = sm[ys[j]:ys[j + 1], xs[i]:xs[i + 1]]
            if bm.size == 0 or bm.mean() < 0.4:
                continue
            k = np.bincount(idx[ys[j]:ys[j + 1], xs[i]:xs[i + 1]][bm], minlength=len(pal)).argmax()
            out[j, i, :3] = pal[k]
            out[j, i, 3] = 255
    return out


def despeckle(spr):
    """去孤立噪点（第 3 轮起按清单 despeckle:true 启用，已通过验图的项保持原样不重处理）：
    ① 不透明且 4-邻接不透明数 ≤1 的孤点 → 透明；② 颜色与 8-邻接全不相同、但邻域存在
    ≥5 个同色的像素 → 改为邻域众数色。只改单像素，不动整块形状。"""
    import numpy as np
    out = spr.copy()
    h, w = spr.shape[:2]
    op = spr[..., 3] > 0
    pad = np.pad(op, 1)
    n4 = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
    out[op & (n4 <= 1)] = 0
    op = out[..., 3] > 0
    for y in range(h):
        for x in range(w):
            if not op[y, x]:
                continue
            me = tuple(out[y, x, :3])
            neigh = [tuple(out[j, i, :3]) for j in range(max(0, y - 1), min(h, y + 2))
                     for i in range(max(0, x - 1), min(w, x + 2)) if (j, i) != (y, x) and op[j, i]]
            if me in neigh or len(neigh) < 5:
                continue
            best = max(set(neigh), key=neigh.count)
            if neigh.count(best) >= 5:
                out[y, x, :3] = best
    return out


def to_target(raw_path: str, item: dict):
    """raw → 目标尺寸成品：抠图 → 主体框 → 调色板多数表决降采样（32px 16 色 / 更小 10 色）
    → 1px 描边（#181420，4-邻接外轮廓，同 house style）。portrait 底边贴边（头肩像），
    其余四周各留 1px 给描边。返回 RGBA Image。"""
    import numpy as np
    from PIL import Image
    w, h = item["size"]
    fit = item.get("fit", "contain")
    rgb, mask = cutout(raw_path)
    box, mask = subject_bbox(mask)
    if box is None:
        return Image.new("RGBA", (w, h))
    inner_w, inner_h = w - 2, (h - 1 if fit == "portrait" else h - 2)
    spr = palette_downsample(rgb, mask, box, (inner_w, inner_h), fit, 16 if max(w, h) >= 32 else 10)
    if item.get("despeckle"):
        spr = despeckle(spr)
    canvas = np.zeros((h, w, 4), np.uint8)
    canvas[1:1 + inner_h, 1:1 + inner_w] = spr
    op = canvas[..., 3] > 0
    pad = np.pad(op, 1)
    ring = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]) & ~op
    canvas[ring, :3] = OUTLINE_RGB
    canvas[ring, 3] = 255
    return Image.fromarray(canvas, "RGBA")


def run_process(items: list) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    n = 0
    for it in items:
        raw = os.path.join(RAW_DIR, f"{it['id']}.png")
        if not os.path.exists(raw):
            print(f"  [process] {it['id']}: no raw, skip")
            continue
        to_target(raw, it).save(os.path.join(OUT_DIR, f"{it['id']}.png"))
        n += 1
    print(f"[gen_ai_art] processed {n} -> {OUT_DIR}")


def run_sheets(items: list, kind: str) -> None:
    """验图拼板。raw：原生成图缩 256 缩略，4x3 一页；cmp：左原图右新图，各放大到
    ≤96px（NEAREST，像素级可读），3x4 一页——看目标尺寸下的真实观感。"""
    from PIL import Image, ImageDraw
    os.makedirs(SHEET_DIR, exist_ok=True)
    cells = []
    for it in items:
        if kind == "raw":
            p = os.path.join(RAW_DIR, f"{it['id']}.png")
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA")
                im.thumbnail((256, 256), Image.LANCZOS)
                cells.append((it["id"], [im]))
        else:
            p_new = os.path.join(OUT_DIR, f"{it['id']}.png")
            p_old = os.path.join(BACKUP_DIR, it["out"]) if os.path.exists(
                os.path.join(BACKUP_DIR, it["out"])) else os.path.join(ROOT, it["out"])
            if os.path.exists(p_new):
                pair = []
                for p in (p_old, p_new):
                    im = Image.open(p).convert("RGBA")
                    z = max(1, 96 // max(im.size))
                    pair.append(im.resize((im.size[0] * z, im.size[1] * z), Image.NEAREST))
                cells.append((it["id"], pair))
    cols, rows = (4, 3) if kind == "raw" else (3, 4)
    per = cols * rows
    for page in range((len(cells) + per - 1) // per):
        chunk = cells[page * per:(page + 1) * per]
        cw = 272 if kind == "raw" else 224
        chh = 290 if kind == "raw" else 130
        sheet = Image.new("RGBA", (cols * cw, rows * chh), (48, 52, 60, 255))
        dr = ImageDraw.Draw(sheet)
        for i, (cid, ims) in enumerate(chunk):
            x0, y0 = (i % cols) * cw + 8, (i // cols) * chh + 8
            x = x0
            for im in ims:
                sheet.paste(im, (x, y0), im)
                x += im.size[0] + 12
            dr.text((x0, y0 + (262 if kind == "raw" else 104)), cid, fill=(235, 235, 235, 255))
        sheet.save(os.path.join(SHEET_DIR, f"{kind}_{page}.png"))
    print(f"[gen_ai_art] {len(cells)} cells -> {SHEET_DIR}/{kind}_*.png")


# ---------------------------------------------------------------- 视觉验图（对话模型）
# 验图模型经会话同一中转（ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN，Messages API），
# 盲测已证实视觉可用。输入 = 原生成图（主体/风格判定）+ 目标尺寸放大图（可读性判定）；
# 输出严格 JSON {"pass": bool, "score": 1-10, "issues": [...]}，结果落 art_ai/qa.json。
QA_MODEL = "claude-opus-5-5"
QA_WORKERS = 5
# 口径校准（实测）：16~32px 下该模型对原程序化素材的绝对分同样只有 2~4 分——绝对阈值
# 在此尺寸无区分度。改为「盲评 A/B 对照」：新旧同尺寸同放大倍率、左右随机、双向各评一次
# 抵消位置偏置；两次都判新图更好且新图单评分 ≥ QA_MIN_SCORE 才算通过。
QA_MIN_SCORE = 5

QA_RUBRIC = """You are the art director of a retro 16-bit pixel-art dungeon crawler (Soul Knight style).
Two candidate sprites for the SAME in-game slot follow, both at the true in-game size of {w}x{h} px,
enlarged with nearest-neighbour: image A first, image B second. The dark 1px outline is the house style.
The slot is: {slot}
Judge them strictly AS IN-GAME SPRITES AT THIS SIZE: instantly readable silhouette, identifiable subject
for this slot, clean pixel-art look (no noise/stray pixels/mud), cohesive 16-bit style, appeal.
Reply with ONLY one JSON object, no prose:
{{"better": "A"|"B", "score_A": <1-10>, "score_B": <1-10>, "issues_A": ["..."], "issues_B": ["..."]}}"""


def _png_b64(im) -> str:
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def _zoom(im):
    from PIL import Image
    z = max(1, 256 // max(im.size))
    bg = Image.new("RGBA", (im.size[0] * z, im.size[1] * z), (48, 52, 60, 255))
    up = im.resize(bg.size, Image.NEAREST)
    bg.paste(up, (0, 0), up)
    return bg


def _judge(a, b, item: dict) -> dict:
    base = os.environ.get("ANTHROPIC_BASE_URL", "").rstrip("/")
    tok = os.environ.get("ANTHROPIC_AUTH_TOKEN", "") or os.environ.get("ANTHROPIC_API_KEY", "")
    if not base or not tok:
        raise RuntimeError("QA endpoint not configured (ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN)")
    w, h = item["size"]
    body = {"model": QA_MODEL, "max_tokens": 400, "messages": [{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": _png_b64(_zoom(a))}},
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": _png_b64(_zoom(b))}},
        {"type": "text", "text": QA_RUBRIC.format(w=w, h=h, slot=item.get("slot", item["prompt"]))}]}]}
    req = urllib.request.Request(f"{base}/v1/messages", data=json.dumps(body).encode("utf-8"), headers={
        "x-api-key": tok, "Authorization": f"Bearer {tok}", "anthropic-version": "2023-06-01",
        "content-type": "application/json"})
    resp = json.loads(_urlopen(req, 180).decode("utf-8"))
    text = "".join(c.get("text", "") for c in resp.get("content", []))
    return json.loads(text[text.find("{"):text.rfind("}") + 1])


def qa_one(item: dict) -> dict:
    """新图（art_ai/out）vs 原件（backup 优先，否则 art/generated 现件）双向盲评。"""
    from PIL import Image
    new_p = os.path.join(OUT_DIR, f"{item['id']}.png")
    bak = os.path.join(BACKUP_DIR, item["out"])
    old_p = bak if os.path.exists(bak) else os.path.join(ROOT, item["out"])
    new, old = Image.open(new_p).convert("RGBA"), Image.open(old_p).convert("RGBA")
    last = ""
    for attempt in range(4):
        try:
            r1 = _judge(new, old, item)             # 新图在 A 位
            r2 = _judge(old, new, item)             # 新图在 B 位
            wins = (r1.get("better") == "A") + (r2.get("better") == "B")
            new_score = (int(r1.get("score_A", 0)) + int(r2.get("score_B", 0))) / 2
            old_score = (int(r1.get("score_B", 0)) + int(r2.get("score_A", 0))) / 2
            return {"pass": wins == 2 and new_score >= QA_MIN_SCORE, "wins": wins,
                    "score": new_score, "orig_score": old_score,
                    "issues": list(dict.fromkeys(r1.get("issues_A", []) + r2.get("issues_B", [])))[:6]}
        except Exception as e:                            # noqa: BLE001
            last = f"{type(e).__name__}: {e}"
            time.sleep(5 * (attempt + 1))
    return {"pass": False, "wins": 0, "score": 0, "orig_score": 0, "issues": [f"QA call failed: {last[:120]}"]}


def run_qa(items: list) -> dict:
    """并发 A/B 验图（需先 --process），合并写 art_ai/qa.json。返回本轮 {id: verdict}。"""
    path = os.path.join(AI_DIR, "qa.json")
    allv = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    items = [i for i in items if os.path.exists(os.path.join(OUT_DIR, f"{i['id']}.png"))]
    out = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=QA_WORKERS) as ex:
        for it, v in zip(items, ex.map(qa_one, items)):
            out[it["id"]] = v
            mark = "PASS" if v["pass"] else "FAIL"
            print(f"  [qa {mark}] {it['id']} wins={v['wins']}/2 new={v['score']} orig={v['orig_score']} "
                  f"{v['issues'][:2]}", flush=True)
    allv.update(out)
    json.dump(allv, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    n_fail = sum(1 for v in out.values() if not v["pass"])
    print(f"[gen_ai_art] qa: {len(out) - n_fail} pass / {n_fail} fail -> {path}")
    return out


def run_apply(items: list) -> None:
    """out/ → art/generated/。首次替换前把原件备份进 art_ai/backup/（--restore 回滚）。"""
    n = 0
    for it in items:
        src = os.path.join(OUT_DIR, f"{it['id']}.png")
        if not os.path.exists(src):
            print(f"  [apply] {it['id']}: no out, skip")
            continue
        dst = os.path.join(ROOT, it["out"])
        bak = os.path.join(BACKUP_DIR, it["out"])
        if not os.path.exists(bak):
            os.makedirs(os.path.dirname(bak), exist_ok=True)
            shutil.copy2(dst, bak)
        shutil.copy2(src, dst)
        n += 1
    print(f"[gen_ai_art] applied {n} -> art/generated/ (backup: {BACKUP_DIR})")


def run_restore(items: list) -> None:
    n = 0
    for it in items:
        bak = os.path.join(BACKUP_DIR, it["out"])
        if os.path.exists(bak):
            shutil.copy2(bak, os.path.join(ROOT, it["out"]))
            n += 1
    print(f"[gen_ai_art] restored {n} originals")


def run_generate(items: list, style: str, workers: int, force: bool) -> None:
    os.makedirs(RAW_DIR, exist_ok=True)
    if not force:
        todo = [i for i in items if not os.path.exists(os.path.join(RAW_DIR, f"{i['id']}.png"))]
        if len(todo) < len(items):
            print(f"[gen_ai_art] skip {len(items) - len(todo)} already in raw/ (--force to redo)")
        items = todo
    if not items:
        print("[gen_ai_art] nothing to generate")
        return
    key = load_key()
    print(f"[gen_ai_art] generating {len(items)} items, {workers} workers, models={MODELS}", flush=True)
    t0 = time.time()
    fails = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(gen_item, key, it, style) for it in items]
        for fut in concurrent.futures.as_completed(futs):
            iid, ok, err = fut.result()
            if ok:
                print(f"  [ok] {iid} ({time.time() - t0:.0f}s)", flush=True)
            else:
                fails.append(iid)
                print(f"  [FAIL] {iid}: {err[:150]}", flush=True)
    print(f"[gen_ai_art] done in {time.time() - t0:.0f}s: ok={len(items) - len(fails)} "
          f"fail={len(fails)} {fails}", flush=True)
    if fails:
        sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="逗号分隔 id 过滤")
    ap.add_argument("--workers", type=int, default=WORKERS)
    ap.add_argument("--force", action="store_true", help="重新生成已存在的 raw（验图不合格用）")
    ap.add_argument("--sheets", choices=("raw", "cmp"), help="生成验图拼板")
    ap.add_argument("--qa", action="store_true", help="对话模型视觉验图 → art_ai/qa.json")
    ap.add_argument("--process", action="store_true", help="raw → out 降采样")
    ap.add_argument("--apply", action="store_true", help="out → art/generated/（先备份原件）")
    ap.add_argument("--restore", action="store_true", help="从 art_ai/backup/ 回滚原件")
    args = ap.parse_args()
    data = load_manifest()
    items = data["items"]
    if args.only:
        wanted = {x.strip() for x in args.only.split(",") if x.strip()}
        items = [i for i in items if i["id"] in wanted]
    if args.sheets:
        run_sheets(items, args.sheets)
    elif args.qa:
        run_qa(items)
    elif args.process:
        run_process(items)
    elif args.apply:
        run_apply(items)
    elif args.restore:
        run_restore(items)
    else:
        run_generate(items, data["style_prefix"], args.workers, args.force)


if __name__ == "__main__":
    main()
