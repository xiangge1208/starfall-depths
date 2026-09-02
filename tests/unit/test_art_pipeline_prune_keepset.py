# m4-a2 P0 prune keep-set 回归守卫（由 tests/unit/test_art_pipeline.gd 以子进程驱动）。
# 场景：gen_placeholder_art.py 全量 main() 尾部的 _prune_stale() 此前 keep 集只含
# M1 SPEC + MANIFEST.md/_preview.png/.gitkeep，会把非 M1 管线拥有的子树
# （fx/、trials/ 归 M3；icon/ 归 X-C）当"陈旧残留"静默删除，且顺带删光全部
# *.import sidecar。断言（dry-run，不动真实仓库磁盘）：
#   A) 真实库（最坏情形 SPEC 为空）：prune 计划零条目落入 fx/trials/icon 三子树，
#      且零 *.import 条目；
#   B) 真实库豁免集：_prune_exempt_dirs() ⊇ {fx, trials, icon}（fx 同时被
#      MANIFEST_M3.md 标记规则覆盖，trials/icon 靠显式登记兜底）；
#   C) 合成目录端到端：M1 陈旧残留被计划清理，而三豁免子树（含子树内的
#      M1 陈旧文件）、清单标记子树、.gitkeep、*.import、SPEC 内文件全部保留。
# 全程零磁盘副作用（仅 tempfile 内写读删）；argv[1] = 仓库 tools/ 目录绝对路径。
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import gen_placeholder_art as g  # noqa: E402

# ---- A) 真实库 worst-case dry-run：SPEC 为空（= 一切 M1 资产皆"陈旧"）时，
#         三豁免子树与 .import 仍必须零删除。
real_plan = g._prune_plan()
foreign = [r for r in real_plan
           if r.split("/", 1)[0] in ("fx", "trials", "icon") or r.endswith(".import")]
if foreign:
    print("FAIL: real-repo prune plan would delete foreign/sidecar files:")
    for r in foreign[:20]:
        print("  -", r)
    sys.exit(1)

# ---- B) 真实库豁免集断言（fx 由显式集 + MANIFEST_M3.md 标记双路命中）
exempt = g._prune_exempt_dirs()
missing = {"fx", "trials", "icon"} - exempt
if missing:
    print("FAIL: exempt dirs missing:", sorted(missing))
    sys.exit(1)
for sub in ("fx", "trials", "icon"):
    if not (g.OUT / sub).is_dir():
        print(f"FAIL: expected real subtree missing: {g.OUT / sub}")
        sys.exit(1)

# ---- C) 合成目录端到端（OUT/SPEC 指向 tempfile，模块对象还原用 try/finally）
orig_out, orig_spec = g.OUT, list(g.SPEC)
try:
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "generated"
        spec_entries = [
            ("characters/hero_a.png", "", "", ""),
            ("tiles/floor_a.png", "", "", ""),
        ]
        files = {
            # M1 SPEC 内 → 保留
            "characters/hero_a.png": b"p",
            "tiles/floor_a.png": b"p",
            # 管线根产物 → 保留
            "MANIFEST.md": b"m",
            "_preview.png": b"v",
            # .gitkeep / .import → 保留
            "pickups/.gitkeep": b"",
            "enemies/old_mob.png.import": b"i",
            # M1 陈旧残留 → 计划清理
            "enemies/retired_slug.png": b"p",
            "weapons/retired_weapon.png": b"p",
            # 三豁免子树（含混入的 M1 陈旧文件）→ 零删除
            "fx/spark_x_strip4.png": b"p",
            "fx/MANIFEST_M3.md": b"m",
            "fx/fx_m1_stale.png": b"p",
            "fx/fx_m1_stale.png.import": b"i",
            "trials/factor_x.png": b"p",
            "icon/icon_256.png": b"p",
            # 通用规则：未来新生成器子树（带 MANIFEST_* 标记）→ 整树豁免
            "traps/trap_a.png": b"p",
            "traps/MANIFEST_TRAPS.md": b"m",
            # 无标记无登记的新子树 → 仍按残留清理（约定见 PRUNE_FOREIGN_DIRS 注释）
            "loose/unknown.png": b"p",
        }
        for rel, data in files.items():
            p = out / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        g.OUT = out
        g.SPEC[:] = spec_entries
        plan = sorted(g._prune_plan())
        expected = sorted(["enemies/retired_slug.png", "weapons/retired_weapon.png",
                           "loose/unknown.png"])
        if plan != expected:
            print("FAIL: synthetic prune plan mismatch")
            print("  expected :", expected)
            print("  actual   :", plan)
            sys.exit(1)
        # 执行路径也验证一遍（在 tempfile 内安全）：删后豁免子树文件仍在
        removed = g._prune_stale()
        if sorted(removed) != expected:
            print("FAIL: _prune_stale removal mismatch:", sorted(removed))
            sys.exit(1)
        for rel in files:
            if rel in expected:
                if (out / rel).exists():
                    print(f"FAIL: stale file not removed: {rel}")
                    sys.exit(1)
            elif not (out / rel).exists():
                print(f"FAIL: kept file was removed: {rel}")
                sys.exit(1)
finally:
    g.OUT, g.SPEC = orig_out, orig_spec

print("KEEPSET-GUARD-OK")
