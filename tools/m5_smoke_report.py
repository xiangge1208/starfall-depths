"""M5-T11 bot 20 人冒烟聚合（附录 L §5 验收口径）。

读 docs/superpowers/reports/m5-bot-smoke-seg*.json（balance_bot --hero-list 逐局
row 带 hero 字段），按英雄与附录 L §4 类型分组输出 markdown 表。纯聚合，零随机。
用法：python tools/m5_smoke_report.py [--glob PATTERN] > report_fragment.md
"""
import argparse
import glob
import json
import statistics
import sys

LEGACY = ["vanguard", "ranger", "engineer", "mage", "guardian", "assassin"]

# 附录 L §4 差异化矩阵的「距离带」维度，外加现役 6 人归类（同口径）。
GROUPS = {
    "贴身近战": ["assassin", "lycan"],
    "长柄/近战节奏": ["monk"],
    "标准远程": ["vanguard", "ranger", "engineer", "mage", "hunter", "gunslinger",
               "bard", "mirage", "necro", "warlock", "staranchor"],
    "高风险血线": ["berserk"],
    "控区/铺场": ["timeweaver", "alchemist"],
    "生存/工事": ["guardian", "cleric", "bulwark"],
}


def load(pattern):
    rows = []
    for f in sorted(glob.glob(pattern)):
        with open(f, encoding="utf-8") as fh:
            rows += json.load(fh)["results"]
    return rows


def med(xs):
    return statistics.median(xs) if xs else 0.0


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--glob", default="docs/superpowers/reports/m5-bot-smoke-seg*.json")
    args = ap.parse_args(argv)
    rows = load(args.glob)
    by = {}
    for r in rows:
        by.setdefault(r["hero"], []).append(r)

    legacy_rooms = [r["rooms"] for h in LEGACY for r in by.get(h, [])]
    legacy_med = med(legacy_rooms)
    out = []
    w = out.append
    w("| 英雄 | 局数 | 结局（死/停/超时/崩） | 房数中位 | 击杀中位 | 时长中位 | vs 现役中位 | 种子明细（房/结局） |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for hid in LEGACY + [h for h in by if h not in LEGACY]:
        rs = by.get(hid, [])
        if not rs:
            w("| %s | 0 | — | — | — | — | — | 未跑 |" % hid)
            continue
        oc = {k: sum(1 for r in rs if r["outcome"] == k) for k in ("death", "stalled", "timeout", "crash")}
        rm = med([r["rooms"] for r in rs])
        km = med([r["kills"] for r in rs])
        dm = med([r["duration_s"] / 60 for r in rs])
        rel = (rm - legacy_med) / legacy_med if legacy_med else 0.0
        seeds = " ".join("%d:%d/%s" % (r["seed"] % 1000, r["rooms"], r["outcome"][0]) for r in rs)
        w("| %s | %d | %d/%d/%d/%d | %.1f | %.0f | %.1f min | %+.0f%% | %s |" % (
            hid, len(rs), oc["death"], oc["stalled"], oc["timeout"], oc["crash"],
            rm, km, dm, rel * 100, seeds))
    w("")
    w("现役 6 人房数中位 = %.1f（n=%d）。" % (legacy_med, len(legacy_rooms)))
    w("")
    w("| 类型分组 | 成员 | 组房数中位 | vs 现役中位 |")
    w("| --- | --- | --- | --- |")
    for g, members in GROUPS.items():
        ran = [h for h in members if by.get(h)]
        gr = [r["rooms"] for h in ran for r in by[h]]
        if not gr:
            w("| %s | %s | — | 未跑 |" % (g, "/".join(members)))
            continue
        gm = med(gr)
        rel = (gm - legacy_med) / legacy_med if legacy_med else 0.0
        w("| %s | %s | %.1f | %+.0f%% |" % (g, "/".join(ran), gm, rel * 100))
    w("")
    tot = {k: sum(1 for r in rows if r["outcome"] == k) for k in ("death", "stalled", "timeout", "crash")}
    w("合计 %d 局：死 %d / 停滞 %d / 超时 %d / 崩溃 %d。" % (
        len(rows), tot["death"], tot["stalled"], tot["timeout"], tot["crash"]))
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
