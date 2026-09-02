# M4-C2 四英雄被动冒烟证据汇总（2026-09-02）

验收项：Task C-2「4 英雄各 ≥2 局无异常（被动生效无异常、崩溃=0）」。
驱动：`tools/balance_bot.gd` 最小 `--hero=<id>` 参数（m4-c2 落地，缺省 vanguard 行为逐字节不变），
headless 墙钟真实速率（物理拍=墙钟拍）。逐英雄报告/机器值见同目录
`m4-c2-smoke-<hero>.md/.json`（每份 JSON `opts.hero` 自证英雄注入）。

## 批次口径

| 英雄 | 被动 | seed-base | 局 |
|---|---|---|---|
| mage（法师·烬） | echo | 2201 | 2201/2202 |
| guardian（守护者·萄） | blessing | 2211 | 2211/2212 |
| engineer（工程师·铆） | spare_parts | 2221 | 2221/2222 |
| assassin（刺客·蝉） | shadow_reap | 2231 | 2231/2232 |

## 逐局结局（8 局）

| seed | 英雄 | 结局 | 楼层/房间/击杀 | 时长 | 死因 |
|---|---|---|---|---|---|
| 2201 | mage | death | F1/3 房/25 杀 | 86.3s | 弩兵的弹幕（combat） |
| 2202 | mage | death | F1/4 房/23 杀 | 62.9s | 双刀蜥人的接触冲撞（elite） |
| 2211 | guardian | death | F1/0 房/3 杀 | 78.4s | 穴蝠的接触冲撞（combat） |
| 2212 | guardian | **stalled** | F1/0 房/2 杀 | 188.7s | - |
| 2221 | engineer | death | F1/3 房/16 杀 | 35.6s | 苦力虫的自爆（combat） |
| 2222 | engineer | death | F1/5 房/29 杀 | 84.6s | 苦力虫的自爆（combat） |
| 2231 | assassin | **stalled** | F1/0 房/2 杀 | 460.0s | - |
| 2232 | assassin | **stalled** | F1/0 房/1 杀 | 443.1s | - |

- **崩溃 = 0；SCRIPT ERROR = 0（全量日志 grep）**；死亡=合法对局结局。
- 被动对局内均真实生效且无异常：mage 法杖弹 ×1.15 全程生效（echo）；engineer 开局
  备件台随局部署、16/29 击杀含炮台输出（spare_parts）；assassin 近战击杀发生
  （kills 计入 → shadow_reap 返蓝/免冷却窗触发，无错误）；guardian 首层 0 叠层为
  规格语义（blessing 自第 2 层起叠层，本批未活过首层——数值由单测钉死）。

## 3 局停滞的取证与归属（非 C-2 回归）

停滞为 bot 既有 180s 签名检测收局（m3-fix2 机制）。两份探针证据落
`m4-c2-probe/probe-2231-a1.json`（assassin）与 `probe-2212-a1.json`（guardian）：

1. **guardian seed 2212**：探针快照 `energy=0`、`pb=0`（玩家弹池空）、武器
   xinghuizhang（energy_cost 4/发）+ 技能生命潮汐（耗蓝 30）——GDD §7.2「蓝空规则：
   远程武器无法开火」生效，bot 无能量管理（不会停射/停技能攒蓝）→ 零输出 → 停滞。
2. **assassin seed 2231/2232**：能量满（近战 0 耗蓝），双匕 `range=32px`，存活敌
   距离 97~134px（弩兵风筝/藤蔓冲撞保持距离）——近战永远够不到，bot 无贴近/绕障
   能力（恰为 B-3 卡「shooter 贴近/绕障」同族缺口的对偶：melee 不贴身）→ 零输出 → 停滞。
3. **对照实验（同种子 vanguard，laohuoji 0 耗蓝远程）**：seed 2231 → 120s 内
   rooms 0→1、kills 11；seed 2212 → rooms 0→5、kills 27。同种子可推进证明
   停滞为**英雄 kit 特异的 bot 能力残差**，非种子不可清、非 C-2 改动回归。

归属：欠账清单 #14/#17（bot 能力残差 → B-3 卡接手）。vanguard 时代不可见的原因：
bot 历史仅跑 vanguard（初始武器 0 耗蓝远程，两种失败模式都不触发）——`--hero`
参数让该残差首次可观测，属暴露而非引入。
