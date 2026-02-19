# Fatebound Action Dungeon MVP Plan

## 目标

在保留现有 rules-first 架构（`rule_engine.gd + json + intent/narrative stub`）的前提下，将当前“文本结算 MVP”升级为“可操作战斗 MVP”，形成类似元气骑士的 2D 俯视角地牢体验。

核心原则不变：
1. 规则引擎是唯一真相来源，所有数值变化由规则结果驱动。
2. AI 仅负责意图 JSON 与叙事文本，不得新增机制效果。
3. 先最小可玩闭环，再扩展美术与内容。

## 当前状态（2026-02-15）

已完成：
1. 房间推进（god/combat/secret）与 10 房 demo 路径。
2. 姿态选择（restraint/pact/blasphemy）与规则偏置。
3. 战斗阈值判定（`min_atk/min_def/corruption_threshold/fate_threshold`）与解释日志。
4. 延迟诅咒（pending effects + triggers + conditions）。
5. 可复现测试（determinism、姿态差异、延迟触发）。

未完成（本计划聚焦）：
1. 实时操作战斗（移动、射击、敌人行为、命中反馈）。
2. 文本房间与实时战斗房的运行时切换。
3. 战斗事件与规则事件点（on_combat_start/end）的完整联动。

## 里程碑计划

## Phase 1 - Combat Sandbox（当前立即开始）

目标：先做独立可玩的 2D 战斗白盒，验证“数值有用、操作可感知”。

范围：
1. 新增 `scenes/combat/CombatSandbox.tscn` + `scripts/combat/combat_sandbox.gd`。
2. 支持玩家移动（WASD/方向键）+ 鼠标朝向射击。
3. 敌人追击与接触伤害。
4. 读取 `data/rooms.json` 的 combat 房阈值字段（enemy/min_atk/min_def/...）。
5. 面板显示：玩家状态、阈值、实时日志、胜负结果。

验收：
1. 可独立运行并在 3-5 分钟内完成一场战斗。
2. ATK/DEF 不达标时玩家明显更吃亏（掉血速度可见）。
3. 日志能解释为什么吃亏（阈值命中原因）。

## Phase 2 - Rules Runtime Bridge

目标：把实时战斗事件接入现有规则系统，而不是在战斗脚本里直接改核心数值。

范围：
1. 统一战斗事件桥接接口（combat start/end、用钥匙、进密室）。
2. 战斗开始调用规则触发 `on_combat_start` 债务。
3. 战斗结束调用规则触发 `on_combat_end` + `after_room`。
4. 将战斗战利品和惩罚写回主状态机。

验收：
1. 同 seed + 同输入 + 同姿态，结果可复现。
2. 规则日志与战斗日志可对齐。

## Phase 3 - Main Loop Integration

目标：将 `Main.tscn` 的文本流程升级为“房间类型驱动场景切换”。

范围：
1. combat_room 进入实时战斗子场景。
2. god_room/secret_room 继续使用现有对话 UI。
3. 完成 10 房 run 的可玩闭环（死亡或通关结局）。

验收：
1. 前 3 房即可体验姿态差异 + 战斗阈值 + 延迟诅咒。
2. UI 清晰区分“规则结果”和“叙事文本”。

## Phase 4 - Content and Feel

目标：提升“可玩性”而不是只看日志。

范围：
1. 至少 2 种敌人行为（追击/远程）。
2. 1-2 种可感知 reward（射速、伤害、护盾）。
3. 1-2 种可感知 curse（战斗开场扣血、用钥匙代价）。

验收：
1. 10 分钟可玩，且玩家能说出“我在做选择并承担后果”。

## 风险与对策

风险 1：实时战斗与规则引擎双写状态。
对策：核心状态只在 `apply_resolution()` 落地，战斗层只产出事件和中间结果。

风险 2：无高质量美术导致“看起来不完整”。
对策：白盒阶段用 Kenney 资源/几何体，优先验证玩法与反馈。

风险 3：节奏失控（系统太多一次性并行）。
对策：严格按 Phase 分批提交，每阶段都有可运行验收点。

## 本次提交后立即执行项

1. 创建 CombatSandbox 场景并可独立运行。
2. 接入 rooms.json 的 combat 参数。
3. 输出可解释阈值日志与胜负反馈。
