# Project Structure

更新时间：2026-03-02

## 1. 顶层目录

- `assets/`：字体与美术资源（含 Kenney 素材）
- `data/`：核心配置 JSON（房间、实体、奖励、诅咒、AI stub 等）
- `docs/`：设计、分析、重构与计划文档
- `skills/`：本地 Codex 技能目录（自动化流程）
- `scenes/`：Godot 场景资源
- `scripts/`：GDScript 逻辑代码（玩法、规则、UI、测试）
- `project.godot`：Godot 项目配置（当前主场景：`res://scenes/DungeonRun.tscn`）

## 2. 场景层（scenes）

- `scenes/DungeonRun.tscn`
  - 当前主玩法场景（动作地牢白盒）
  - 包含 HUD、祈福面板、小地图、日志
- `scenes/Main.tscn`
  - 早期规则流程入口（保留）
- `scenes/combat/CombatSandbox.tscn`
  - 战斗沙箱测试场景
- `scenes/ui/*.tscn`
  - HUD / Dialog / Room 等拆分 UI 组件（保留）

## 3. 脚本层（scripts）

### 3.1 当前主线玩法

- `scripts/dungeon/dungeon_run.gd`
  - 房间探索与战斗循环
  - 锁门/钥匙机制
  - 祈福房交互（清怪 + 距离门槛 + 输入冻结）
  - 神像流程（直接固定 3 轮对话 -> 规则结算）
  - 小地图点亮与相邻预判
  - 日志输出与数值结算

### 3.2 规则与 AI stub（rules-first）

- `scripts/core/rule_engine.gd`
- `scripts/core/intent_parser.gd`
- `scripts/core/narrative_generator.gd`
- `scripts/ai_stub.gd`
- `scripts/ai/dialogue_ai_gateway.gd`
  - provider 切换（`stub/openai`）
  - openai 失败自动降级
  - 意图 schema 校验与叙事白名单

说明：该层用于规则决策、意图解析、叙事生成的分层验证，保证“规则是唯一真相来源”。

### 3.3 测试

- `scripts/tests/run_tests.gd`
- `scripts/tests/test_fate_rule_engine.gd`
- `scripts/tests/test_rule_engine.gd`
- `scripts/tests/test_dialogue_ai_gateway.gd`

当前覆盖：可复现性、姿态偏置（规则层）、战斗阈值、延迟诅咒触发。

## 4. 数据层（data）

- `data/dungeon_layout.json`
  - 动作地牢房间图、敌人配置、锁门、钥匙奖励、祈福池、宝箱奖励
- `data/rooms.json`
  - 规则引擎战斗/房间配置（历史与规则线并存）
- `data/gods.json`
- `data/rewards.json`
- `data/curses.json`
- `data/entities.json`
- `data/game_config.json`
- `data/ai_stub.json`
- `data/dialogue_config.json`
- `data/ai_provider.json`
- `data/prompts/*.prompt.txt`（每神明独立对话提示词）

## 5. 当前运行模式

### 5.1 Action Dungeon（默认）

- 入口：`res://scenes/DungeonRun.tscn`
- 操作：WASD、鼠标左键
- 循环：清房 -> 选路 -> 解锁 -> 祈福 -> 终局

### 5.2 Rules/Text 原型（保留）

- 主要用于规则系统与 AI stub 的离线验证。

## 6. 运行与验证

### GUI

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

### Headless 场景加载

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --scene res://scenes/DungeonRun.tscn --log-file ./godot-scene.log --quit
```

### 测试

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://scripts/tests/run_tests.gd --log-file ./godot-tests.log
```

## 7. 自动化 Skill

- `skills/docs-sync-and-commit/SKILL.md`
  - 检查“代码/数据改动是否同步文档”
  - 统一执行 `git add .` + `git commit`
- `skills/docs-sync-and-commit/scripts/run.sh`
  - `--no-commit`：仅检查
  - `-m "<message>"`：执行提交

## 8. 版本管理约定

- 规则：每次提交必须保持“可运行/可复现”。
- 建议提交前执行：
  1. 场景 headless 启动
  2. `run_tests.gd`
- 提交信息建议：`feat|fix|docs|test: ...`
