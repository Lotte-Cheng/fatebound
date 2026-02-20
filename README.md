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
3. 生存战斗房支持刷怪上限，刷满后清空余怪即可结算。
4. 清房后通门，带锁路径需钥匙解锁。
5. 祈福房交互：
   - 必须先清怪。
   - 必须靠近神像。
   - 输入请求时角色移动冻结。
6. 教学关（`r01`）操作引导闭环：
   - 分步骤引导：移动 -> 开火 -> 击杀升级 -> 选择构筑。
   - 世界空间动态箭头 + UI 脉冲提示。
   - 固定构筑选项与“刚好升 1 级”刷怪量。
7. 构筑系统 v2（Phase 2B 第一版）：
   - 槽位限制：`weapon/passive/godsend/debt`。
   - 预算进阶：`tier_cost` + 每级预算增长 + 前置标签约束。
   - 标签协同：满足 `synergy_rules` 后触发额外效果。
   - 升级面板显示槽位与标签，日志输出协同激活来源。
8. 怪物死亡掉落经验晶体，角色靠近后自动吸附拾取；HUD 显示经验条。
9. 刷怪调参支持 `data/spawn_profiles.json -> global_tuning` 一处总控（刷怪频率/怪物数值/后期怪海强度）。
10. 小地图探索点亮 + 相邻房间有限预判。
11. 日志持续输出战斗、解锁、祈福、结算事件。
12. 战场可视区域会按左侧 HUD 动态让位，避免文字被遮挡。

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
- 教学关会显示步骤化指引与箭头动画，按提示完成即可学会升级

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
- `docs/BUILD_ROUTE_AND_ENDINGS.md`：完整构筑路线与结局定义（Demo）
- `docs/DEITY_COMMUNION_SYSTEM_SPEC.md`：神像-仪式-召神-对话系统规格
- `docs/GAME_DESIGN_DOCUMENT.md`：设计文档（GDD）
- `docs/PROJECT_BRIEF.md`：项目简述
- `docs/AI_FEASIBILITY_ANALYSIS.md`：AI 可行性分析
- `docs/ENGINE_COMPARISON.md`：Godot 与 UE5 对比

---

## 版本管理

- 已使用 Git 管理项目。
- 建议每个可运行阶段单独提交，提交信息遵循：`feat/fix/docs/test: 摘要`。
