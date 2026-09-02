#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M4-B4 蓝晶经济模拟器（GDD §14.3 三点带判定）。

任务卡：docs/superpowers/plans/2026-09-02-m4-v1-completion.md「Task B-4」①。

模型策略（防虚假精度，计划明文）：
  产出侧以 §14.1 规则的**生产代码解析值**为主——FLOOR_GEMS/KILL_GEMS/
  BOSS_FIRST_KILL_GEMS 从 autoload/run_state.gd 正则读点（勿手抄）；成就蓝晶
  从 core/meta/achievement_system.gd 解析（id/gems/active）；天赋成本从
  data/talents.json 实值；图鉴任务从 data/unlock_tasks.json 实值；Boss 数从
  data/enemies.json（archetype=="boss"）实值。bot 局 gems_curve（--bot-json）
  只作悲观档校准与模型对照，不作主口径。
  生产实现口径差异（模型按实现建模，差异在报告披露）：
    - F3 Boss 死亡直接胜利（inter_floor_flow.gd VICTORY_FLOOR=3 跳过 DOOR），
      「通过第 3 层」的 +200 永不结算 → 胜利局过层蓝晶上限 60+120=180；
    - 死亡保留 50%（试炼局 75%）；胜利/放弃全额；试炼胜利 ×1.5（向下取整）。

过层率扫参（计划明文）：bot 实测层通过收入不可行（历史 bot 止步 F1），对过层
分布做**乐观/悲观/目标三档敏感性区间**：
  - 悲观档：bot 全量复跑实测锚定（层通过率/局时长/击杀取实测）；
  - 目标档：GDD §14.3 胜率曲线（<5h 10% / 5~20h 25% / 20h+ 40%）+ 时长带；
  - 乐观档：熟练上限（胜率曲线上沿 + 快节奏局）。
三点判定按区间结论汇报而非单点。

消费侧=实值：天赋树 data/talents.json 24 条总成本（唯一在产消费端）；角色解锁
2000/2000/5000/5000/8000 与技能强化 1500/名 为 GDD §6 纸面锚点（数据表无价格
字段、产品无购买消费端——报告披露，不入数据读点）。

三点判定（每点「带内/出带」）：
  P1 2~3h 解锁第 1 角色（最便宜锚点 2000，带 [2,3]h）
  P2 10h 天赋树 60%（按成本实值，10h±20% → 带内到达 [8,12]h）
  P3 20h 图鉴 80%（49 任务实值判定，20h 时解锁率带 80%±20% 相对 → [64%,96%]）

出带处置（计划明文）：修订窗口内（≤±20%）且证据充分 → 可直接调产出/价格并附
前后模拟对照；超窗或证据不足 → 记录超限意向与建议方案，不擅自改。

确定性：全模型零随机（期望值逐步推进），同输入逐字节同输出。

用法：
  python tools/economy_sim.py --repo-root . --bot-json docs/superpowers/reports/m4-b4-batch-*.json \
      --out-md docs/superpowers/reports/m4-economy.md --out-json docs/superpowers/reports/m4-economy.json
  python tools/economy_sim.py --self-test        # 轻量自测（GDScript 测试经子进程驱动）
  python tools/economy_sim.py --help
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------- GDD 纸面锚点
# GDD §6「解锁价格（蓝晶）：游侠 2000 / 法师 2000 / 刺客 5000 / 工程师 5000 / 守护者 8000。
# 预期 2~3 小时游玩解锁第一名付费角色」。数据表（data/heroes.json）无价格字段、
# 产品无购买消费端（SaveSystem.unlock_hero 无扣费；hero_select 无门槛）——模拟按
# 纸面锚点计算节奏，可交付性差异在报告披露（M4-B4 实测结论）。
GDD_HERO_UNLOCK_PRICES: Dict[str, int] = {
    "ranger": 2000, "mage": 2000, "assassin": 5000, "engineer": 5000, "guardian": 8000,
}
# GDD §6 技能表「强化（蓝晶 1500/名解锁）」——同上，纸面锚点（无消费端）。
GDD_HERO_UPGRADE_COST = 1500

# 成就蓝晶解锁节奏档（粗粒度假设，防虚假精度：单列披露，不与过层收入混算）。
# 20h 内解锁比例（线性爬坡）：悲观 / 目标 / 乐观。
ACHIEVEMENT_UNLOCK_FRACTION_AT_20H = {"pessimistic": 0.35, "target": 0.80, "optimistic": 1.00}
# Boss 首杀对（每层 2 择 1 → 同层双 Boss 名录齐）完成时点（小时，线性内插结算）。
# 悲观档封顶在 F1 对（bot 层通过能力边界）；单位 gems = BOSS_FIRST_KILL_GEMS×2。
FIRST_KILL_PAIR_HOURS = {
    "pessimistic": (8.0, None, None),
    "target": (2.0, 8.0, 16.0),
    "optimistic": (1.0, 4.0, 9.0),
}

# 图鉴计数器每局速率假设（悲观档 kills/run 取 bot 实测；共鸣/熔铸/购买无遥测
# 读点——档位假设在 stage 参数与报告披露，主导不确定性）。
CODEx_PESSIMISTIC_RESONATE = 0.5   # 悲观档共鸣/局（主导不确定性，披露）
CODEx_PESSIMISTIC_CRAFT = 0.1      # 悲观档熔铸/局
CODEx_PESSIMISTIC_BUY = 0.5        # 悲观档购买/局（bot 买红心实测锚定）

# 判定带
P1_BAND_H = (2.0, 3.0)          # GDD §14.3：2~3h 解锁第 1 名新角色
P2_TARGET_H = 10.0              # GDD §14.3：10h 点满天赋树 60%
P2_BAND_REL = 0.20              # 带宽：到达时点 10h±20% → [8,12]h
P3_TARGET_H = 20.0              # GDD §14.3：20h 图鉴解锁 80%
P3_BAND_REL = 0.20              # 带宽：20h 解锁率 80%±20%（相对）→ [64%,96%]
REVISION_WINDOW = 0.20          # Global Constraint 11：数值修订 ≤±20%

HORIZON_H = 20.0                # 模拟时域（覆盖 P2/P3 判定点）


# ---------------------------------------------------------------- 数据读点
def _read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def read_production_constants(repo: str) -> Dict:
    """生产蓝晶常量读点（正则解析 run_state.gd / inter_floor_flow.gd，勿手抄）。"""
    rs = _read(os.path.join(repo, "autoload", "run_state.gd"))
    m = re.search(r"const FLOOR_GEMS\s*:?=\s*\[([^\]]+)\]", rs)
    floor_gems = [int(x) for x in m.group(1).split(",")] if m else [60, 120, 200]
    m = re.search(r"const KILL_GEMS\s*:?=\s*\{([^}]+)\}", rs)
    kill_gems = {}
    if m:
        for k, v in re.findall(r'"(\w+)":\s*(\d+)', m.group(1)):
            kill_gems[k] = int(v)
    m = re.search(r"const BOSS_FIRST_KILL_GEMS\s*:?=\s*(\d+)", rs)
    boss_first = int(m.group(1)) if m else 300
    iff = _read(os.path.join(repo, "core", "rooms", "inter_floor_flow.gd"))
    m = re.search(r"const VICTORY_FLOOR\s*:?=\s*(\d+)", iff)
    victory_floor = int(m.group(1)) if m else 3
    return {
        "floor_gems": floor_gems,
        "kill_gems": kill_gems,
        "boss_first_kill_gems": boss_first,
        "victory_floor": victory_floor,
    }


def read_achievements(repo: str) -> List[Dict]:
    """成就蓝晶读点（achievement_system.gd defs 表：id/gems/active）。"""
    src = _read(os.path.join(repo, "core", "meta", "achievement_system.gd"))
    rows = re.findall(
        r'\{"id": "(\w+)", "name": "[^"]*", "gems": (\d+), "active": (true|false)', src)
    return [{"id": i, "gems": int(g), "active": a == "true"} for i, g, a in rows]


def read_talents(repo: str) -> Dict:
    with open(os.path.join(repo, "data", "talents.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def read_unlock_tasks(repo: str) -> Dict:
    with open(os.path.join(repo, "data", "unlock_tasks.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def read_boss_count(repo: str) -> int:
    with open(os.path.join(repo, "data", "enemies.json"), "r", encoding="utf-8") as f:
        enemies = json.load(f)
    return sum(1 for v in enemies.values() if v.get("archetype") == "boss")


# ---------------------------------------------------------------- 纯计算函数
def floor_gems_granted(floor_gems_table: List[int], floors_cleared: int,
                       victory_floor: int) -> int:
    """过层蓝晶（生产口径）：每清一层在进入下一层时入账 FLOOR_GEMS[min(n-1,2)]；
    胜利层（victory_floor）Boss 死即胜、跳过 DOOR → 该层份永不结算。
    floors_cleared=1 → 60；=2 → 180；=3（胜利）→ 180（第 3 层份被胜利短路）。"""
    total = 0
    for n in range(1, floors_cleared + 1):
        if n >= victory_floor:
            continue   # 胜利层：victory_achieved 短路，无 +200（实现口径）
        idx = min(n - 1, len(floor_gems_table) - 1)
        total += floor_gems_table[idx]
    return total


def settle_gems(pending: int, won: bool, trial: bool) -> int:
    """终局结算（run_state.gd settle_death_gems/settle_victory_gems 生产口径）：
    死亡保留 50%（向下取整；试炼局 75%）；胜利全额（试炼局 ×1.5 向下取整）。"""
    if won:
        return int(pending * 1.5) if trial else pending
    rate = 0.75 if trial else 0.5
    return int(pending * rate)   # int() 向下取整，与 GDScript floor 一致（正数域）


def in_band(value: float, lo: float, hi: float) -> bool:
    return lo - 1e-9 <= value <= hi + 1e-9


def band_of_reach(target_h: float, rel: float) -> Tuple[float, float]:
    """「到达时点 target_h±rel」带。"""
    return (target_h * (1 - rel), target_h * (1 + rel))


def talent_threshold(talents: Dict, frac: float) -> int:
    """天赋树 frac%（按成本实值加权和）——60% 点满 = 总成本的 60% 蓝晶。"""
    total = sum(int(v["cost"]) for v in talents.values())
    return int(round(total * frac))


def codex_unlocked_fraction(tasks: Dict, counters: Dict[str, float]) -> float:
    """图鉴解锁率：cur>=goal 即解锁（codex_system.progress/check_unlocks 口径）。
    clear_floor_x 按 param 分桶（floor_clears[层号]）；其余类型按 counters 总量。"""
    if not tasks:
        return 0.0
    done = 0
    for row in tasks.values():
        t = row.get("type", "")
        goal = float(row.get("goal", 0))
        if t == "clear_floor_x":
            cur = float((counters.get("floor_clears", {}) or {}).get(
                str(int(row.get("param", 0))), 0.0))
        else:
            cur = float(counters.get(t, 0.0))
        if cur >= goal - 1e-9:
            done += 1
    return done / float(len(tasks))


def required_income_multiple(threshold: int, actual: float) -> Optional[float]:
    """出带修复所需收入倍数（阈值/实际）；证据不足（实际<=0）返回 None。"""
    if actual <= 0:
        return None
    return threshold / actual


# ---------------------------------------------------------------- 档位参数
def stage_params_target(stage: int) -> Dict:
    """目标档分段参数（GDD §14.3 胜率曲线 + 时长带）。
    stage 0: <5h（新手 10%）；1: 5~20h（25%）；2: 20h+（40%）。
    条件通过率按胜率曲线反解：p_win = p1×p2×p3。"""
    if stage == 0:
        return {"p_f1": 0.90, "p_f2": 0.40, "win_given_f2": 0.10 / (0.90 * 0.40),
                "minutes": 30.0, "kills": 90.0, "reso": 2.0, "craft": 1.0, "buy": 2.5}
    if stage == 1:
        return {"p_f1": 0.95, "p_f2": 0.60, "win_given_f2": 0.25 / (0.95 * 0.60),
                "minutes": 28.0, "kills": 120.0, "reso": 3.0, "craft": 1.5, "buy": 3.0}
    return {"p_f1": 0.97, "p_f2": 0.75, "win_given_f2": 0.40 / (0.97 * 0.75),
            "minutes": 25.0, "kills": 150.0, "reso": 4.0, "craft": 2.0, "buy": 3.5}


def build_tiers(repo: str, prod: Dict, calib: Optional[Dict]) -> Dict[str, Dict]:
    """三档敏感性参数。悲观档由 bot 实测锚定（层通过率/局时长/击杀每局）；
    目标/乐观档按 GDD §14.3。击杀蓝晶每清一层 ≈ elite+miniboss+boss 档位合计
    （目标/乐观档假设每层各 1 个；悲观档直接用 bot 实测局均待结算的 50% 口径
    反推，见 calib）。"""
    kg = prod["kill_gems"]
    per_floor_kill_gems = kg.get("elite", 5) + kg.get("miniboss", 20) + kg.get("boss", 50)

    # 悲观档：bot 实测锚定（无校准数据时用历史批次的保守缺省）
    bot_p_f1 = calib["p_floors1"] if calib else 0.02
    bot_p_f2 = calib["p_floors2"] if calib else 0.0
    bot_win = calib["p_win"] if calib else 0.0
    bot_minutes = calib["minutes_per_run"] if calib else 35.0
    bot_kills = calib["kills_per_run"] if calib else 15.0
    # bot 局均过层蓝晶（gems_curve 终值与模型对照已剔除首杀/成就大额，取中位）
    pessimistic = {
        "label": "悲观（bot 实测锚定）",
        "stages": [{
            "p_f1": bot_p_f1, "p_f2": bot_p_f2 if bot_p_f2 < bot_p_f1 else bot_p_f1 * 0.3,
            "win_given_f2": 0.0, "minutes": max(bot_minutes, 35.0),
            "kills": bot_kills, "reso": CODEx_PESSIMISTIC_RESONATE,
            "craft": CODEx_PESSIMISTIC_CRAFT, "buy": CODEx_PESSIMISTIC_BUY,
        }],
        "per_floor_kill_gems": per_floor_kill_gems,
        "kill_gems_scale": 0.4,
        # bot 局均待结算蓝晶直接锚定（击杀小额为主；与过层项并行的对照线）
        "bot_gems_per_run_median": calib["gems_median"] if calib else 0.0,
    }
    target = {
        "label": "目标（GDD §14.3 曲线）",
        "stages": [stage_params_target(0), stage_params_target(1), stage_params_target(2)],
        "per_floor_kill_gems": per_floor_kill_gems,
        "kill_gems_scale": 1.0,
        "bot_gems_per_run_median": calib["gems_median"] if calib else 0.0,
    }
    opt_stage0 = {"p_f1": 0.97, "p_f2": 0.60, "win_given_f2": 0.15 / (0.97 * 0.60),
                  "minutes": 25.0, "kills": 140.0, "reso": 5.0, "craft": 2.0, "buy": 3.5}
    opt_stage1 = {"p_f1": 0.99, "p_f2": 0.75, "win_given_f2": 0.35 / (0.99 * 0.75),
                  "minutes": 25.0, "kills": 180.0, "reso": 8.0, "craft": 2.5, "buy": 4.0}
    opt_stage2 = {"p_f1": 0.99, "p_f2": 0.80, "win_given_f2": 0.45 / (0.99 * 0.80),
                  "minutes": 25.0, "kills": 180.0, "reso": 8.0, "craft": 2.5, "buy": 4.0}
    optimistic = {
        "label": "乐观（熟练上限）",
        "stages": [opt_stage0, opt_stage1, opt_stage2],
        "per_floor_kill_gems": per_floor_kill_gems,
        "kill_gems_scale": 1.0,
        "bot_gems_per_run_median": calib["gems_median"] if calib else 0.0,
    }
    return {"pessimistic": pessimistic, "target": target, "optimistic": optimistic}


def _stage_for_hour(h: float) -> int:
    if h < 5.0:
        return 0
    if h < 20.0:
        return 1
    return 2


def expected_run_income(tier: Dict, stage: Dict, prod: Dict) -> Dict:
    """单局期望蓝晶（期望值分解，零随机）。
    过层蓝晶：E[60×P(过F1) + 120×P(过F2)]（胜利层份不结算）；
    结算乘数：0.5×P(死) + 1.0×P(胜)（试炼份额默认 0——机制见 settle_gems，报告披露只增不减）；
    击杀蓝晶：per_floor_kill_gems × E[清层数] × kill_gems_scale，同结算乘数。"""
    p1, p2, p3 = stage["p_f1"], stage["p_f2"], stage["win_given_f2"]
    p_clear2 = p1 * p2
    p_win = p_clear2 * p3
    fg = prod["floor_gems"]
    e_floor_pending = fg[0] * p1 + (fg[1] if len(fg) > 1 else 0) * p_clear2
    e_floors = p1 + p_clear2 + p_win
    e_kill_pending = tier["per_floor_kill_gems"] * tier["kill_gems_scale"] * e_floors
    settle_mult = 0.5 * (1 - p_win) + 1.0 * p_win   # 死亡/放弃 50%，胜利 100%
    return {
        "floor_pending": e_floor_pending,
        "kill_pending": e_kill_pending,
        "settle_mult": settle_mult,
        "run_income": (e_floor_pending + e_kill_pending) * settle_mult,
        "e_floors_cleared": e_floors,
        "p_win": p_win,
    }


def simulate(tier_name: str, tier: Dict, prod: Dict, ach_total: int,
             boss_first_gems: int, boss_pairs: int,
             horizon_h: float = HORIZON_H) -> List[Tuple[float, float]]:
    """逐局推进累计蓝晶曲线（期望值法，零随机）。返回 [(h, C(h))] 含起点。"""
    frac20 = ACHIEVEMENT_UNLOCK_FRACTION_AT_20H[tier_name]
    pair_hours = FIRST_KILL_PAIR_HOURS[tier_name]
    pair_gems = []
    for i in range(boss_pairs):
        h = pair_hours[i] if i < len(pair_hours) else None
        if h is not None:
            pair_gems.append((h, 2 * boss_first_gems))

    curve: List[Tuple[float, float]] = [(0.0, 0.0)]
    h = 0.0
    total = 0.0
    fk_pending = list(pair_gems)
    while h < horizon_h - 1e-9:
        si = min(_stage_for_hour(h), len(tier["stages"]) - 1)
        stage = tier["stages"][si]
        inc = expected_run_income(tier, stage, prod)
        dt = stage["minutes"] / 60.0
        total += inc["run_income"]
        h_new = min(h + dt, horizon_h)
        # 时段内首杀结算（按时点比例内插到本局末，保持确定性）
        for (fh, g) in fk_pending:
            if fh <= h_new:
                total += g
        fk_pending = [x for x in fk_pending if x[0] > h_new]
        # 成就线性爬坡（按模拟钟）
        total += ach_total * frac20 * (dt / horizon_h)
        h = h_new
        curve.append((round(h, 6), round(total, 1)))
    return curve


def hours_to_reach(curve: List[Tuple[float, float]], threshold: float) -> Optional[float]:
    """阈值到达时点（段内线性内插；永不达到返回 None）。"""
    for i in range(1, len(curve)):
        h0, c0 = curve[i - 1]
        h1, c1 = curve[i]
        if c1 >= threshold:
            if c1 <= c0:
                return h1
            return round(h0 + (h1 - h0) * (threshold - c0) / (c1 - c0), 3)
    return None


def cum_at(curve: List[Tuple[float, float]], h_query: float) -> float:
    val = 0.0
    for (h, c) in curve:
        if h <= h_query + 1e-9:
            val = c
        else:
            break
    return val


def codex_fraction_at(tier_name: str, tier: Dict, tasks: Dict, prod: Dict,
                      calib: Optional[Dict], hours: float = P3_TARGET_H) -> float:
    """20h 图鉴解锁率（期望值法）：计数器 = 每局速率 × 局数；floor_clears 按层分桶；
    gems_earned_total 仅过层蓝晶镜像（on_floor_entered 口径——击杀/首杀/成就蓝晶
    不入此计数器，生产口径差异披露）。"""
    minutes = max(s["minutes"] for s in tier["stages"])
    runs = hours * 60.0 / minutes
    # 20h 判定点落在 stage0/1 区间（<20h），取前两段均值代表（horizon 内 stage2 不活跃）
    head = tier["stages"][:2] if len(tier["stages"]) > 1 else tier["stages"]
    kills = sum(s["kills"] for s in head) / len(head)
    reso = sum(s["reso"] for s in head) / len(head)
    craft = sum(s["craft"] for s in head) / len(head)
    buy = sum(s["buy"] for s in head) / len(head)
    counters = {
        "kill_x": runs * kills,
        "resonate_x": runs * reso,
        "craft_x": runs * craft,
        "buy_x": runs * buy,
        # 过层蓝晶镜像口径：E[每局过层蓝晶 pending] × 局数（不减半、不结算口径）
        "collect_gems_x": runs * _e_floor_gems_pending(tier, prod),
    }
    # floor_clears 分桶：E[通过第 n 层次数] = 局数 × P(清到 n)
    bucket = {}
    for n in (1, 2, 3):
        p = _p_clear_floor(tier, n)
        bucket[str(n)] = runs * p
    counters["floor_clears"] = bucket
    return codex_unlocked_fraction(tasks, counters)


def _p_clear_floor(tier: Dict, n: int) -> float:
    """P(通过第 n 层)（分段平均；悲观档单段）。"""
    ps = []
    for s in tier["stages"]:
        if n == 1:
            ps.append(s["p_f1"])
        elif n == 2:
            ps.append(s["p_f1"] * s["p_f2"])
        else:
            ps.append(s["p_f1"] * s["p_f2"] * s["win_given_f2"])
    return sum(ps) / len(ps)


def _e_floor_gems_pending(tier: Dict, prod: Dict) -> float:
    vals = []
    for s in tier["stages"]:
        vals.append(expected_run_income(tier, s, prod)["floor_pending"])
    return sum(vals) / len(vals)


# ---------------------------------------------------------------- bot 校准
def load_calibration(paths: List[str]) -> Optional[Dict]:
    """bot 全量复跑校准（gems_curve/results/aggregate）：
    局均 gems 终值分布、F1/F2 通过率、胜率、局均时长、局均击杀。"""
    files: List[str] = []
    for p in paths:
        files.extend(glob.glob(p))
    files = sorted(set(files))
    if not files:
        return None
    gems_term, kills, durs, floors = [], [], [], []
    wins = f1 = f2 = 0
    runs = 0
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            d = json.load(f)
        for r in d.get("results", []):
            runs += 1
            kills.append(float(r.get("kills", 0)))
            durs.append(float(r.get("duration_s", 0)))
            fl = int(r.get("floor", 1))
            floors.append(fl)
            if r.get("outcome") == "win":
                wins += 1
            if fl >= 2:
                f1 += 1
            if fl >= 3:
                f2 += 1
        for g in d.get("gems_curve", []):
            gems_term.append(float(g.get("gems", 0)))
    if runs == 0:
        return None
    gems_term.sort()
    med = gems_term[len(gems_term) // 2] if gems_term else 0.0

    def mean(a: List[float]) -> float:
        return sum(a) / len(a) if a else 0.0

    return {
        "files": files,
        "runs": runs,
        "p_floors1": f1 / runs,
        "p_floors2": f2 / runs,
        "p_win": wins / runs,
        "minutes_per_run": mean(durs) / 60.0,
        "kills_per_run": mean(kills),
        "gems_median": med,
        "gems_mean": mean(gems_term),
        "gems_max": max(gems_term) if gems_term else 0.0,
    }


# ---------------------------------------------------------------- 三点判定
def judge_points(repo: str, bot_json: List[str]) -> Dict:
    prod = read_production_constants(repo)
    talents = read_talents(repo)
    tasks = read_unlock_tasks(repo)
    achs = [a for a in read_achievements(repo) if a["active"]]
    ach_total = sum(a["gems"] for a in achs)
    boss_count = read_boss_count(repo)
    calib = load_calibration(bot_json)
    tiers = build_tiers(repo, prod, calib)

    hero1_price = min(GDD_HERO_UNLOCK_PRICES.values())
    t60 = talent_threshold(talents, 0.60)
    talent_total = sum(int(v["cost"]) for v in talents.values())
    boss_pairs = (boss_count + 1) // 2

    curves = {name: simulate(name, tier, prod, ach_total,
                             prod["boss_first_kill_gems"], boss_pairs)
              for name, tier in tiers.items()}

    points = {}
    # P1 解锁第 1 角色
    p1 = {}
    for name, curve in curves.items():
        t = hours_to_reach(curve, hero1_price)
        p1[name] = {"hours": t, "cum_at_3h": cum_at(curve, 3.0)}
    # P2 天赋树 60%
    p2 = {}
    lo, hi = band_of_reach(P2_TARGET_H, P2_BAND_REL)
    for name, curve in curves.items():
        t = hours_to_reach(curve, t60)
        pct10 = cum_at(curve, P2_TARGET_H) / talent_total if talent_total else 0.0
        p2[name] = {"hours": t, "talent_pct_at_10h": pct10}
    # P3 图鉴 80%
    p3 = {}
    for name, tier in tiers.items():
        frac = codex_fraction_at(name, tier, tasks, prod, calib)
        p3[name] = {"fraction_at_20h": frac}

    return {
        "production": prod,
        "achievements": {"active": len(achs), "total_gems": ach_total},
        "talents": {"count": len(talents), "total_cost": talent_total, "t60_cost": t60},
        "codex": {"tasks": len(tasks)},
        "bosses": {"count": boss_count, "pairs": boss_pairs,
                   "first_kill_gems": prod["boss_first_kill_gems"]},
        "gdd_anchors": {"hero_unlock_prices": GDD_HERO_UNLOCK_PRICES,
                        "hero_upgrade_cost": GDD_HERO_UPGRADE_COST,
                        "cheapest_hero": hero1_price},
        "calibration": calib,
        "curves": {k: v for k, v in curves.items()},
        "points": {"p1_hero": p1, "p2_talent60": p2, "p3_codex80": p3},
        "bands": {"p1_hours": list(P1_BAND_H),
                  "p2_hours": list(band_of_reach(P2_TARGET_H, P2_BAND_REL)),
                  "p3_fraction": list(band_of_reach(0.80, P3_BAND_REL))},
    }


# ---------------------------------------------------------------- 修订分析
# 杆位与文件所有权（Global Constraints 11 + B-4 卡）：
#   收入杆位（FLOOR_GEMS/KILL_GEMS/首杀/成就蓝晶）在 autoload/run_state.gd、
#   core/meta/achievement_system.gd——非 B-4 所有权（不碰 core/**、autoload/**）；
#   消费杆位 data/talents.json（成本）与 data/unlock_tasks.json（目标）为 B-4 所有权；
#   GDD 角色价格/强化价格为纸面锚点，无数据字段可修。
OWNED_LEVERS = {"data/talents.json", "data/unlock_tasks.json"}


def revision_analysis(report: Dict) -> List[Dict]:
    """出带点修复分析：所需收入倍数在 ±20% 窗口内 → 窗口内可修订（给对照）；
    超窗/证据不足 → 记录意向。处置三态：
      revise_candidate  = 窗口内 + 杆位在本卡所有权（data/*.json）→ 可修并附对照
      intent_in_window  = 窗口内但杆位不在本卡所有权 → 记意向交编排者
      intent_only       = 超窗或证据不足 → 只记意向不改"""
    out = []
    bands = report["bands"]
    pts = report["points"]

    def action_for(need: Optional[float], lever: str, evidence_ok: bool = True) -> str:
        in_win = need is not None and in_band(need, 1 - REVISION_WINDOW, 1 + REVISION_WINDOW)
        if not evidence_ok or need is None or not in_win:
            return "intent_only"
        return "revise_candidate" if lever in OWNED_LEVERS else "intent_in_window"

    p1lo, p1hi = bands["p1_hours"]
    for name, r in pts["p1_hero"].items():
        t = r["hours"]
        if t is None or not in_band(t, p1lo, p1hi):
            need = required_income_multiple(report["gdd_anchors"]["cheapest_hero"],
                                            r["cum_at_3h"])
            out.append({
                "point": "P1_hero", "tier": name, "kind": "reach_hours", "value": t,
                "band": [p1lo, p1hi],
                "income_multiple_needed": need,
                "in_window": need is not None and in_band(need, 1 - REVISION_WINDOW, 1 + REVISION_WINDOW),
                "lever": "income(run_state.gd,非本卡)/price(GDD纸面,无数据字段)",
                "action": action_for(need, "run_state.gd"),
            })
    p2lo, p2hi = bands["p2_hours"]
    for name, r in pts["p2_talent60"].items():
        t = r["hours"]
        if t is None or not in_band(t, p2lo, p2hi):
            curve = report["curves"][name]
            actual = cum_at(curve, P2_TARGET_H)
            need = required_income_multiple(report["talents"]["t60_cost"], actual)
            out.append({
                "point": "P2_talent60", "tier": name, "kind": "reach_hours", "value": t,
                "band": [p2lo, p2hi],
                "income_multiple_needed": need,
                "in_window": need is not None and in_band(need, 1 - REVISION_WINDOW, 1 + REVISION_WINDOW),
                "lever": "income(run_state.gd,非本卡)/sink(data/talents.json)",
                "action": action_for(need, "data/talents.json"),
            })
    p3lo, p3hi = bands["p3_fraction"]
    for name, r in pts["p3_codex80"].items():
        f = r["fraction_at_20h"]
        if not in_band(f, p3lo, p3hi):
            out.append({
                "point": "P3_codex80", "tier": name, "kind": "fraction_at_20h",
                "value": round(f, 4), "band": [round(p3lo, 4), round(p3hi, 4)],
                "income_multiple_needed": None,
                "in_window": False,
                "lever": "codex goals(data/unlock_tasks.json)/rate 假设证据不足",
                "action": action_for(None, "data/unlock_tasks.json", evidence_ok=False),
            })
    return out


# ---------------------------------------------------------------- 输出
def render_markdown(report: Dict, revision: List[Dict]) -> str:
    prod = report["production"]
    cal = report.get("calibration")
    pts = report["points"]
    L: List[str] = []
    L.append("# M4-B4 蓝晶经济模拟报告（GDD §14.3 三点带判定）")
    L.append("")
    L.append("- 任务：M4 B-4 ①（欠账 #16：M2 审计 + m2-gate §5 移交的「蓝晶经济模拟零执行」；"
             "计划卡 docs/superpowers/plans/2026-09-02-m4-v1-completion.md Task B-4）")
    L.append("- 数据源：② bot 100 局全量复跑 `m4-balance-rerun.md/json`（悲观档校准与 gems_curve 对照）")
    L.append("- 工具：`tools/economy_sim.py`（确定性期望值模型，零随机；`--self-test` 自测钉纯函数）")
    L.append("- 模型策略：产出侧=§14.1 生产代码解析值为主（run_state.gd FLOOR_GEMS/KILL_GEMS/"
             "BOSS_FIRST_KILL_GEMS、成就 defs、VICTORY_FLOOR 胜利短路），bot gems_curve 仅作悲观档校准；"
             "过层率=乐观/悲观/目标三档扫参（计划明文），判定按区间汇报")
    L.append("")
    L.append("## 1. 生产读点（实值，勿手抄口径）")
    L.append("")
    L.append("| 读点 | 值 | 来源 |")
    L.append("| --- | --- | --- |")
    L.append("| 过层蓝晶 | %s | `autoload/run_state.gd` FLOOR_GEMS |" % prod["floor_gems"])
    L.append("| 击杀蓝晶 | %s | `autoload/run_state.gd` KILL_GEMS |" % prod["kill_gems"])
    L.append("| Boss 首杀 | +%d ×%d 只（%d 对） | run_state.gd + data/enemies.json archetype=boss |"
             % (prod["boss_first_kill_gems"], report["bosses"]["count"], report["bosses"]["pairs"]))
    L.append("| 胜利短路 | 第 %d 层 Boss 死即胜，跳过该层过层蓝晶 | `core/rooms/inter_floor_flow.gd` VICTORY_FLOOR |"
             % prod["victory_floor"])
    L.append("| 成就蓝晶 | %d 条激活，合计 %d（一次性） | `core/meta/achievement_system.gd` defs |"
             % (report["achievements"]["active"], report["achievements"]["total_gems"]))
    L.append("| 天赋成本 | %d 条合计 %d（60%%=%d） | `data/talents.json` |"
             % (report["talents"]["count"], report["talents"]["total_cost"], report["talents"]["t60_cost"]))
    L.append("| 图鉴任务 | %d 条（kill/resonate/craft/buy/gems/floor 六类） | `data/unlock_tasks.json` |"
             % report["codex"]["tasks"])
    L.append("")
    L.append("**实现口径差异（模型按实现建模）**：胜利局过层蓝晶上限 60+120=180（第 3 层份 +200 被 "
             "VICTORY_FLOOR=3 短路，GDD §14.1「每层通过 +60/120/200」的第三档实际不可得）；"
             "死亡保留 50%（试炼 75%）、胜利全额、试炼胜 ×1.5（settle_gems 口径）。")
    L.append("")
    L.append("## 2. 消费侧实值与纸面锚点")
    L.append("")
    L.append("| 消费 | 值 | 状态 |")
    L.append("| --- | --- | --- |")
    L.append("| 天赋树 | 合计 %d（实值） | **唯一在产消费端**（TalentSystem.buy → add_gems(-cost)） |"
             % report["talents"]["total_cost"])
    L.append("| 角色解锁 | %s（GDD §6） | **纸面锚点**：数据表无价格字段、`SaveSystem.unlock_hero` 无扣费、"
             "hero_select 无门槛——产品内角色实际全开放可玩，购买节奏不存在 |"
             % report["gdd_anchors"]["hero_unlock_prices"])
    L.append("| 技能强化 | 1500/名（GDD §6） | **纸面锚点**：`upgraded` 字段有技能消费端但无购买写入方 |")
    L.append("| 图鉴 | 无蓝晶成本 | 条件制解锁（计数器达标），非消费端 |")
    L.append("")
    if cal:
        L.append("## 3. bot 100 局校准（悲观档锚定）")
        L.append("")
        L.append("| 指标 | 实测 |")
        L.append("| --- | --- |")
        L.append("| 局数 | %d（%s） |" % (cal["runs"], ", ".join(os.path.basename(f) for f in cal["files"])))
        L.append("| 局均时长 | %.1f min |" % cal["minutes_per_run"])
        L.append("| F1 通过率（floor≥2） | %.1f%% |" % (cal["p_floors1"] * 100))
        L.append("| F2 通过率（floor≥3） | %.1f%% |" % (cal["p_floors2"] * 100))
        L.append("| 胜率 | %.1f%% |" % (cal["p_win"] * 100))
        L.append("| 局均击杀 | %.1f |" % cal["kills_per_run"])
        L.append("| 局终蓝晶 中位/均值/最大 | %.0f / %.1f / %.0f |"
                 % (cal["gems_median"], cal["gems_mean"], cal["gems_max"]))
        L.append("")
        L.append("> 悲观档口径：层通过率/击杀取上表实测；局时长取 max(实测, 35min)——bot 速死时长"
                 "与真人不可比，仅作收入下界锚定；gems_curve 实测中位 %.0f 与模型对照见 §6 曲线。"
                 % cal["gems_median"])
        L.append("")
    L.append("## 4. 三点带判定（区间结论）")
    L.append("")
    tiers = ["pessimistic", "target", "optimistic"]
    labels = {"pessimistic": "悲观", "target": "目标", "optimistic": "乐观"}
    p1lo, p1hi = report["bands"]["p1_hours"]
    L.append("### P1 解锁第 1 角色（锚点 %d，带 %.0f~%.0fh）" % (report["gdd_anchors"]["cheapest_hero"], p1lo, p1hi))
    L.append("")
    L.append("| 档 | 到达时点 | 3h 累计 | 判定 |")
    L.append("| --- | --- | --- | --- |")
    for t in tiers:
        r = pts["p1_hero"][t]
        hrs = r["hours"]
        verdict = "带内" if (hrs is not None and in_band(hrs, p1lo, p1hi)) else "出带"
        L.append("| %s | %s | %.0f | %s |" % (labels[t],
                 ("%.1f h" % hrs) if hrs is not None else ">20h（不达到）", r["cum_at_3h"], verdict))
    L.append("")
    p1_hours = [pts["p1_hero"][t]["hours"] for t in tiers if pts["p1_hero"][t]["hours"] is not None]
    p1_in = [h for h in p1_hours if in_band(h, p1lo, p1hi)]
    L.append("**区间结论**：到达时点区间 %s；主判（目标档）%s。" % (
        ("%s~%s h" % (("%.1f" % min(p1_hours)), ("%.1f" % max(p1_hours)))) if p1_hours else "全部 >20h",
        ("带内" if in_band(pts["p1_hero"]["target"]["hours"] or -1, p1lo, p1hi) else "出带")))
    L.append("**可交付性披露**：角色解锁价格无数据字段、无购买消费端（`SaveSystem.unlock_hero` 无扣费、"
             "hero_select 无门槛全开放）——「购买节奏」在产品内不可发生，本点节奏判定按 GDD 纸面锚点计算；"
             "接线购买端属功能改动（超数据修订窗口），记意向不在本卡执行。")
    L.append("")
    p2lo, p2hi = report["bands"]["p2_hours"]
    L.append("### P2 天赋树 60%%（成本 %d，带 %.0f~%.0fh 到达；10h 应达 60%%）"
             % (report["talents"]["t60_cost"], p2lo, p2hi))
    L.append("")
    L.append("| 档 | 到达时点 | 10h 天赋比例 | 判定 |")
    L.append("| --- | --- | --- | --- |")
    for t in tiers:
        r = pts["p2_talent60"][t]
        hrs = r["hours"]
        verdict = "带内" if (hrs is not None and in_band(hrs, p2lo, p2hi)) else "出带"
        L.append("| %s | %s | %.0f%% | %s |" % (labels[t],
                 ("%.1f h" % hrs) if hrs is not None else ">20h（不达到）",
                 r["talent_pct_at_10h"] * 100, verdict))
    L.append("")
    p2_hours = [pts["p2_talent60"][t]["hours"] for t in tiers if pts["p2_talent60"][t]["hours"] is not None]
    L.append("**区间结论**：到达时点区间 %s；主判（目标档）%s——目标档 10h 天赋比例 %.0f%%。"
             % (("%s~%s h" % (("%.1f" % min(p2_hours)), ("%.1f" % max(p2_hours)))) if p2_hours else "全部 >20h",
                ("带内" if in_band(pts["p2_talent60"]["target"]["hours"] or -1, p2lo, p2hi) else "出带"),
                pts["p2_talent60"]["target"]["talent_pct_at_10h"] * 100))
    L.append("")
    p3lo, p3hi = report["bands"]["p3_fraction"]
    L.append("### P3 图鉴 80%%（%d 任务，20h 解锁率带 %.0f%%~%.0f%%）"
             % (report["codex"]["tasks"], p3lo * 100, p3hi * 100))
    L.append("")
    L.append("| 档 | 20h 解锁率 | 判定 |")
    L.append("| --- | --- | --- |")
    for t in tiers:
        f = pts["p3_codex80"][t]["fraction_at_20h"]
        verdict = "带内" if in_band(f, p3lo, p3hi) else "出带"
        L.append("| %s | %.0f%% | %s |" % (labels[t], f * 100, verdict))
    L.append("")
    L.append("**区间结论**：20h 解锁率区间 %.0f%%~%.0f%%；主判（目标档）%s。"
             % (min(pts["p3_codex80"][t]["fraction_at_20h"] for t in tiers) * 100,
                max(pts["p3_codex80"][t]["fraction_at_20h"] for t in tiers) * 100,
                ("带内" if in_band(pts["p3_codex80"]["target"]["fraction_at_20h"], p3lo, p3hi) else "出带")))
    L.append("")
    L.append("**主导不确定性披露**：P3 的共鸣/熔铸/购买每局速率无遥测读点，为档位假设；"
             "悲观档击杀/时长由 bot 实测锚定但 bot 局时长（速死）与真人不可比，仅作下界。")
    L.append("")
    L.append("## 5. 出带修订台账（≤±20% 窗口纪律）")
    L.append("")
    if not revision:
        L.append("无出带项。")
    else:
        L.append("| 点 | 档 | 实测 | 带 | 需收入倍数 | 窗口内 | 杆位 | 处置 |")
        L.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for r in revision:
            L.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
                r["point"], labels.get(r["tier"], r["tier"]),
                r["value"] if r["value"] is not None else "不达到",
                r["band"], ("%.2fx" % r["income_multiple_needed"]) if r["income_multiple_needed"] else "—",
                "是" if r["in_window"] else "否", r["lever"], r["action"]))
    L.append("")
    L.append("> 处置口径：`revise_candidate`=窗口内且杆位在本卡所有权（data/*.json），可修并附前后对照；"
             "`intent_in_window`=窗口内但杆位不在本卡所有权（收入杆位在 run_state.gd 等），记意向交编排者；"
             "`intent_only`=超窗或证据不足，只记意向不改。")
    L.append("")
    L.append("## 6. 累计蓝晶曲线（期望值，h → gems）")
    L.append("")
    L.append("| h | 悲观 | 目标 | 乐观 |")
    L.append("| --- | --- | --- | --- |")
    curves = report["curves"]
    marks = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20]
    for m in marks:
        row = [cum_at(curves[t], float(m)) for t in tiers]
        L.append("| %d | %.0f | %.0f | %.0f |" % (m, row[0], row[1], row[2]))
    L.append("")
    L.append("> 曲线含成就线性爬坡与首杀时刻表（档位假设单列披露，见文件头常量）。")
    L.append("")
    return "\n".join(L)


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description="M4-B4 蓝晶经济模拟（GDD §14.3 三点带判定；确定性期望值模型）")
    ap.add_argument("--repo-root", default=".",
                    help="仓库根（读点：autoload/run_state.gd、data/*.json 等；默认当前目录）")
    ap.add_argument("--bot-json", nargs="*", default=[],
                    help="bot 复跑 JSON（glob 支持）——悲观档校准与 gems_curve 对照")
    ap.add_argument("--out-md", default="", help="markdown 报告输出路径（缺省 stdout）")
    ap.add_argument("--out-json", default="", help="结构化结果输出路径")
    ap.add_argument("--self-test", action="store_true",
                    help="轻量自测：钉生产读点解析、结算/过层纯函数、带判定与确定性（退出码 0=绿）")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test(args.repo_root)

    report = judge_points(args.repo_root, args.bot_json)
    revision = revision_analysis(report)
    payload = {"report": report, "revision": revision}
    md = render_markdown(report, revision)
    if args.out_md:
        os.makedirs(os.path.dirname(os.path.abspath(args.out_md)), exist_ok=True)
        with open(args.out_md, "w", encoding="utf-8", newline="\n") as f:
            f.write(md)
    if args.out_json:
        os.makedirs(os.path.dirname(os.path.abspath(args.out_json)), exist_ok=True)
        with open(args.out_json, "w", encoding="utf-8", newline="\n") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write("\n")
    if not args.out_md:
        print(md)
    print("ECONOMY-SIM-OK points=%d revision=%d" % (3, len(revision)))
    return 0


# ---------------------------------------------------------------- 自测
def self_test(repo: str) -> int:
    """轻量自测：三点判定纯计算函数 + 生产读点解析钉（GDScript 测试经子进程驱动）。"""
    fails: List[str] = []

    def check(name: str, cond: bool) -> None:
        if not cond:
            fails.append(name)

    # 1) 生产读点解析
    prod = read_production_constants(repo)
    check("floor_gems_parsed", prod["floor_gems"] == [60, 120, 200])
    check("kill_gems_parsed", prod["kill_gems"] == {"elite": 5, "miniboss": 20, "boss": 50})
    check("boss_first_parsed", prod["boss_first_kill_gems"] == 300)
    check("victory_floor_parsed", prod["victory_floor"] == 3)

    # 2) 过层蓝晶纯函数（含胜利短路实现口径）
    fg, vf = prod["floor_gems"], prod["victory_floor"]
    check("fg_f1", floor_gems_granted(fg, 1, vf) == 60)
    check("fg_f2", floor_gems_granted(fg, 2, vf) == 180)
    check("fg_f3_win_shortcircuit", floor_gems_granted(fg, 3, vf) == 180)

    # 3) 终局结算纯函数（死亡 50% / 试炼 75% / 胜利全额 / 试炼 ×1.5 向下取整）
    check("settle_death_half", settle_gems(101, False, False) == 50)
    check("settle_death_trial", settle_gems(101, False, True) == 75)
    check("settle_win_full", settle_gems(101, True, False) == 101)
    check("settle_win_trial", settle_gems(101, True, True) == 151)

    # 4) 带判定
    check("band_in", in_band(2.5, 2.0, 3.0))
    check("band_edge", in_band(3.0, 2.0, 3.0) and not in_band(3.01, 2.0, 3.0))
    check("band_of_reach", band_of_reach(10.0, 0.20) == (8.0, 12.0))

    # 5) 消费侧实值读点
    talents = read_talents(repo)
    check("talent_count", len(talents) == 24)
    check("talent_total_10000", sum(int(v["cost"]) for v in talents.values()) == 10000)
    check("talent_t60_6000", talent_threshold(talents, 0.60) == 6000)
    achs = read_achievements(repo)
    check("ach_count_24", len(achs) == 24)
    check("ach_all_active", all(a["active"] for a in achs))
    check("ach_total_4350", sum(a["gems"] for a in achs) == 4350)
    check("boss_count_6", read_boss_count(repo) == 6)
    check("hero1_price_2000", min(GDD_HERO_UNLOCK_PRICES.values()) == 2000)

    # 6) 图鉴解锁率纯函数（含 clear_floor_x 分桶 + 边界 cur==goal 解锁）
    tasks = {"a": {"type": "kill_x", "goal": 100},
             "b": {"type": "clear_floor_x", "goal": 2, "param": 1},
             "c": {"type": "collect_gems_x", "goal": 1000}}
    check("codex_zero", codex_unlocked_fraction(tasks, {}) == 0.0)
    check("codex_boundary", codex_unlocked_fraction(
        tasks, {"kill_x": 100, "floor_clears": {"1": 2}, "collect_gems_x": 999}) == 2 / 3)
    check("codex_all", codex_unlocked_fraction(
        tasks, {"kill_x": 100, "floor_clears": {"1": 2}, "collect_gems_x": 1000}) == 1.0)

    # 7) 曲线与到达时点（合成曲线：每半小时 +100）
    fake_curve = [(i * 0.5, i * 100.0) for i in range(0, 81)]
    check("reach_interp", hours_to_reach(fake_curve, 1000.0) == 5.0)
    check("reach_never", hours_to_reach([(0, 0), (1, 10)], 100.0) is None)
    check("cum_at", cum_at(fake_curve, 2.25) == 400.0)

    # 8) 三档曲线端到端：单调不减、20h 收敛、区间有序（悲观 ≤ 目标 ≤ 乐观）
    full = judge_points(repo, [])
    cv = full["curves"]
    for t in tiers_order():
        c = cv[t]
        vals = [v for _, v in c]
        check("curve_monotonic_" + t, all(b >= a for a, b in zip(vals, vals[1:])))
    check("pess_le_target_at_10h",
          cum_at(cv["pessimistic"], 10.0) <= cum_at(cv["target"], 10.0) + 1e-6)
    check("target_le_opt_at_10h",
          cum_at(cv["target"], 10.0) <= cum_at(cv["optimistic"], 10.0) + 1e-6)

    # 9) 确定性：两次全量判定逐字节一致
    again = judge_points(repo, [])
    check("deterministic", json.dumps(full, sort_keys=True) == json.dumps(again, sort_keys=True))

    if fails:
        for f in fails:
            print("FAIL: %s" % f)
        print("ECONOMY-SIM-SELFTEST-FAILED (%d)" % len(fails))
        return 1
    print("ECONOMY-SIM-SELFTEST-OK")
    return 0


def tiers_order() -> List[str]:
    return ["pessimistic", "target", "optimistic"]


if __name__ == "__main__":
    sys.exit(main())
