# T37 光照参与集归因矩阵（task-37 / 评审批处理可复现诊断）

工具：`tools/diag_light_attribution.tscn`（复刻 `perf_probe` F2 压测构图：
`probe_build(2)` 最密战斗房 + 40 注入敌 + 弹池补满 500，节流窗 60fps 采样
240 帧 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`，vsync 关，种子 20260831）。

复现：

```
godot --path . res://tools/diag_light_attribution.tscn            # VAR 缺省 head
VAR=bullets_lit godot --path . res://tools/diag_light_attribution.tscn
# 截图模式（确定性构图，弹幕飞行 30 帧后冻结）：
BULLETS=1 WAIT_FRAMES=30 SHOT_OUT=user://shot.png \
  godot --path . res://tools/diag_light_attribution.tscn
```

`VAR` 语义：
- `head` —— 当前提交口径（地形面/陈设/敌人/玩家/弹幕/预警纹 = `BiomeFx.LIT_ITEM_MASK`，光圈 cull 2）
- `t37_head` —— 回放 T37 首轮 a70305d（弹幕/预警纹退回默认位 1）
- `bullets_lit` / `polys_lit` / `bullets_polys_lit` —— 单变量叠加参与集
- `cull1` —— T37 前全量参与参照；`nolight` —— 无光圈基线参照

## 归因轮（T37 首轮评审前，2026-08-31，两轮合并口径）

| VAR | draw avg | max | 结论 |
|---|---|---|---|
| f1（无 A2 fx） | 108.9 | 206 | 基线 |
| f2（全特效，T37 前） | 148.9~154.6 | 258~279 | 探针 FAIL 同构 |
| f2 + 光圈隐藏 | 115.2~120.3 | 189 | +33~+45 全部来自光圈 |
| f2 + 光圈 cull_mask=0（无条目参与） | 108.8~117.5 | 180~206 | 光圈节点本身零成本 |
| f2 + 剪影 modulate 关（光圈在） | 156.2 | 267 | modulate 无辜（不裂批） |
| f2 + 全敌同贴图 ± modulate | 160.8~171.4 | 268~271 | 贴图同质化不解决（反升） |
| f2 + 仅地形面参与（cull 2） | 115.2~119.3 | 189~201 | 修复成立 |
| f2 + 仅敌人参与（cull 2） | 114.5 | 189 | 修复成立 |
| f2 + 地形面+敌人参与（cull 2） | 109.9~116.6 | 190~195 | 修复成立（T37 首轮落地配置） |

**结论：光圈默认 cull_mask=1 时画布全部条目参与逐项光照重渲，2D 批处理沿
lit/unlit 状态翻转碎裂 → O(穿越次数) 增量；参与集收口到低计数世界条目即归零。
逐敌剪影 modulate 与贴图纹理多样性均与增量无关。**

## 修复轮（评审 Important-1：弹幕/预警纹可读性）

diag 单变量矩阵（第一轮，实现前同机同时段）：

| VAR（F2 满压 500 弹） | draw avg | max |
|---|---|---|
| head（T37 首轮：弹幕/预警纹不参与） | 94.8 | 176 |
| bullets_lit（弹幕真实光照回归） | 98.4 | 136 |
| polys_lit（预警纹回归） | 97.3 | 166 |
| bullets_polys_lit（两者回归） | 98.5 | 150 |
| cull1（T37 前全量参与参照） | 140.7 | 227 |
| nolight（无光圈基线参照） | 88.5 | 143 |

**但 diag 低估了真实光照参与的成本**——探针（含 HUD/伤害数字全管线）同机 A/B：

| 探针 F2（同机相邻时段） | draw avg / max |
|---|---|
| T37 首轮（a70305d，弹幕/预警纹不参与） | 100.4 / 141 |
| 弹幕+预警纹进参与集 | 147.6 / 239（复测 148.5 / 256） |
| **弹幕 self_modulate 折叠 + 预警纹参与（落地配置）** | **101.2 / 158** |

**结论：弹幕真实光照回归在探针口径 +47 draw（diag 只见 +3.7——diag 缺伤害数字/
白闪全管线高频状态翻转，归因下界不可外推），150 预算下否决；改走评审建议的
(a) self_modulate 折叠（逐项 modulate 写入零批处理成本，首轮矩阵 f2_nomod 实证
+0），光圈内弹幕增亮恢复（视觉证据 `t37_fix1_aura_bullet_compare.png`：before 暗
弹 → after 增亮 → cull1 全亮参照）。预警纹计数小，保留真实光照参与（落地配置
探针 F2 101.2，余量 32.5%）。**
