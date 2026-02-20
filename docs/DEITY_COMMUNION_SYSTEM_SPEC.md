# Deity Communion System Spec

更新时间：2026-02-20

## 目标

把“祈福按钮”升级为可感知的完整流程：

1. 神像碑文阅读（了解神像故事与偏好）。
2. 特定仪式召唤神明（消耗资源/满足条件）。
3. 固定轮次对话（建议 3 轮）。
4. 每轮规则判定奖励机会（AI 不直接发奖励）。

## 交互流程

1. 玩家靠近神像 -> 显示碑文摘要与“继续阅读”。
2. 阅读后解锁仪式面板：展示需求与预期风险。
3. 点击执行仪式（成功/失败由规则判定）。
4. 仪式成功则进入神明对话界面。
5. 固定轮次对话结束后输出回合汇总与总结算。

## 固定轮次规则

- 默认 `max_turns = 3`。
- 每轮输入一条玩家话术。
- 每轮输出：
  - `intent_json`
  - `resolution_preview`
  - 神明文本回应
- 达到上限后自动结束并结算。

## 建议系统（玩家辅助）

每轮提供 2-3 条建议表达：

1. 保守建议（低风险）。
2. 平衡建议（中风险）。
3. 激进建议（高风险）。

建议来源：
- 当前神明人设 + 玩家状态 + 当前构筑缺口。
- 先模板生成，后续可接 GPT 改写为自然表达。

## 人设一致性约束

每个神明配置以下字段：

1. `persona`: 语气与价值观。
2. `taboo_topics`: 禁忌点。
3. `favored_requests`: 偏好诉求。
4. `disliked_requests`: 厌恶诉求。
5. `speaking_style`: 用词风格标签。

叙事输出要求：

1. 文本必须符合该神明语气。
2. 禁止输出未在 `resolution` 中出现的数值变化。
3. 出现越界内容时，回退到本地模板回应。

## 数据文件建议

1. `data/statues.json`
   - 碑文、背景故事、仪式需求、绑定神明 id。
2. `data/gods.json`
   - 人设、偏好、禁忌、奖励/诅咒池偏置。
3. `data/dialogue_config.json`
   - `max_turns`, `suggestion_count`, `timeout_sec`。
4. `data/rituals.json`
   - 仪式配方、成功率修正、失败后果。

## API 集成规范（可选）

## Provider 模式

1. `stub`（默认离线）。
2. `openai`（你提供 API 后启用）。

## 调用边界

1. 意图解析：模型必须返回严格 JSON。
2. 叙事生成：模型只接收 `resolution` 进行复述。

## 失败回退

1. API 超时：自动降级到 stub。
2. JSON 校验失败：最多重试 1 次，再降级模板。
3. 叙事越权：丢弃并改用本地文案。

## 接口草案

意图解析输入：
- `player_text`, `god_id`, `turn_index`, `player_state`, `build_tags`

意图解析输出（JSON）：
- `wish_type`, `tone`, `risk_preference`, `constraints[]`, `target`, `ritual_action`

叙事生成输入：
- `god_profile`, `resolution`, `recent_dialogue`

叙事生成输出：
- `narrative_text`（仅文本，无机制字段）
