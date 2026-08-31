# m2-t21 美术管线防回归（由 tests/unit/test_art_pipeline.gd 以子进程驱动）。
# 场景：gen_placeholder_art_m2 导入失败（旧实现 `except ImportError: pass`）时，
# main() 若照常执行 _prune_stale() 会把 M1 SPEC 之外的整棵 M2 子树（数百文件）
# 当"陈旧残留"静默删除。断言：main hard-fail 且 prune 从未执行。
# 全程 stub 生成器函数，零磁盘副作用；argv[1] = 仓库 tools/ 目录绝对路径。
import sys
import types

sys.path.insert(0, sys.argv[1])
import gen_placeholder_art as g  # noqa: E402

pruned = []
g._prune_stale = lambda: pruned.append("P")

# A) 闸门纯函数：M2 未参与 -> RuntimeError 且绝不触碰 prune
try:
    g._prune_after_m2(False)
    print("FAIL: gate(False) did not raise")
    sys.exit(1)
except RuntimeError:
    pass
if pruned:
    print("FAIL: prune ran on gate(False)")
    sys.exit(1)

# B) 闸门放行路径：M2 已参与 -> prune 恰好执行一次
g._prune_after_m2(True)
if pruned != ["P"]:
    print("FAIL: gate(True) did not delegate to prune")
    sys.exit(1)

# C) 端到端：把 M2 模块投毒成导入失败，stub 掉全部生成器（main 除外），
#    main() 必须 hard-fail（ImportError 向上抛），prune 计数不再增长。
for name, val in list(vars(g).items()):
    if name != "main" and not name.startswith("_") and isinstance(val, types.FunctionType):
        setattr(g, name, (lambda *a, **k: None))
g._prune_stale = lambda: pruned.append("P")
sys.modules["gen_placeholder_art_m2"] = None  # import -> ImportError（None 哨兵）
try:
    g.main()
    print("FAIL: main() swallowed m2 import failure")
    sys.exit(1)
except ImportError:
    pass
if len(pruned) != 1:
    print("FAIL: prune executed after m2 import failure")
    sys.exit(1)
print("PRUNE-GATE-OK")
