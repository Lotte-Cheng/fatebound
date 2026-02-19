# Fatebound: The Whispering Gods

## 项目状态

- 状态：`可运行白盒 MVP（Action Dungeon 模式）`
- 引擎：`Godot 4.6`
- 默认入口：`res://scenes/DungeonRun.tscn`
- 核心原则：`Rules-First`（规则与数据驱动，AI 仅做意图/叙事）

---

## 当前可玩内容

1. 房间探索循环（起始/战斗/祈福/宝库）。
2. 实时移动与射击（WASD + 鼠标左键）。
3. 清房后通门，带锁路径需钥匙解锁。
4. 祈福房交互：
   - 必须先清怪。
   - 必须靠近神像。
   - 输入请求时角色移动冻结。
5. 小地图探索点亮 + 相邻房间有限预判。
6. 日志持续输出战斗、解锁、祈福、结算事件。

---

## 技术栈

- Godot 4.x + GDScript
- JSON 配置（`res://data/*.json`）
- Rules-first 架构：
  - 规则层决定数值与效果。
  - AI/stub 层仅做意图 JSON 与叙事文本。

---

## 快速运行

### GUI 运行

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

### Headless 启动校验

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --scene res://scenes/DungeonRun.tscn --log-file ./godot-scene.log --quit
```

### 测试（规则层）

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://scripts/tests/run_tests.gd --log-file ./godot-tests.log
```

---

## 操作说明

- `WASD` / 方向键：移动
- `鼠标左键`：射击
- 清空房间敌人后，移动到门口切换房间
- 祈福房中，靠近神像后可输入祈祷请求并选择祝福

---

## 项目结构

详细结构与职责见：`docs/PROJECT_STRUCTURE.md`

顶层目录：

- `scenes/`：场景资源（当前主场景 `DungeonRun.tscn`）
- `scripts/`：玩法逻辑、规则引擎、测试
- `data/`：房间/神明/奖励/诅咒等 JSON 数据
- `docs/`：方案、重构说明与项目文档
- `assets/`：字体与美术素材

---

## 文档导航

- `docs/PROJECT_STRUCTURE.md`：当前项目构成、模块职责、运行与测试入口
- `docs/DUNGEON_RUNTIME_REWORK.md`：动作地牢运行时重构与现状
- `docs/ACTION_DUNGEON_MVP_PLAN.md`：动作化 MVP 计划
- `docs/GAME_DESIGN_DOCUMENT.md`：设计文档（GDD）
- `docs/PROJECT_BRIEF.md`：项目简述
- `docs/AI_FEASIBILITY_ANALYSIS.md`：AI 可行性分析
- `docs/ENGINE_COMPARISON.md`：Godot 与 UE5 对比

---

## 版本管理

- 已使用 Git 管理项目。
- 建议每个可运行阶段单独提交，提交信息遵循：`feat/fix/docs/test: 摘要`。
