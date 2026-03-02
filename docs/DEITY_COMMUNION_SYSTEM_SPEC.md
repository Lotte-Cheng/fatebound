# Deity Communion System Spec

更新时间：2026-03-02

## 目标

把祈福房交互固定为最直接、可复现的 3 轮神明对话：

1. 清空祈福房敌人。
2. 靠近神像后开启对话面板。
3. 输入一句请求（可自动填充）并发送。
4. 规则引擎结算 reward/curse，叙事只复述结果。
5. 共 3 轮，完成后本房祈福结束。

## 当前交互约束

1. 无碑文步骤。
2. 无仪式步骤。
3. 无姿态按钮（restraint/pact/blasphemy 不再由 UI 选择）。
4. 输入框聚焦时角色移动冻结。
5. 只能在“已清房 + 靠近神像 + 未完成本房祈福”时请求。
6. 交流面板默认隐藏意图/规则 JSON，仅显示聊天记录。
7. 请求发出后显示“神明回应中...”加载动画，等待 AI 返回。

## 每轮输入输出

输入：
- `player_text`
- `room_id/god_id/turn_index`（上下文）

输出展示：
- `intent_json`（AI 或 stub 解析）
- `resolution`（规则引擎输出，唯一有效果来源）
- `narrative_text`（神明文本，不得新增效果）

## 数据文件

1. `data/dialogue_config.json`
   - `max_turns`
   - `suggestion_count`
   - `base_reward_rolls/base_curse_rolls`
   - `reward_chance_curve/curse_chance_curve`
   - `suggestion_templates`（直接文本列表）
2. `data/ai_provider.json`
   - `provider`: `stub` 或 `openai`
   - `api_key_env`: 默认 `OPENAI_API_KEY`
   - `model/timeout/schema/deity_prompt_dir`
3. `data/prompts/*.prompt.txt`
   - `default.prompt.txt`
   - `solune.prompt.txt`
   - `tharos.prompt.txt`
   - `nyra.prompt.txt`
   - `murmur.prompt.txt`
   - 用于定义每位神明的固定说话风格，便于直接编辑。

## AI Provider 规则

1. `stub` 默认可离线运行。
2. `openai` 失败（无 key/超时/JSON 非法）自动回退到 stub。
3. 叙事文本过审失败（越权）也回退到本地模板。

## API Key 配置

OpenAI Key 不写入仓库文件，按环境变量读取：

```bash
export OPENAI_API_KEY="sk-..."
```

若要改变量名，修改 `data/ai_provider.json` 的 `api_key_env` 字段即可。
