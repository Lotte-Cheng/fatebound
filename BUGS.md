# Bug Tracker

## Active Bugs

### [BUG-001] 神像回复内容与其身份不符
**状态**: 待修复
**优先级**: 中
**发现时间**: 2026-03-10

**描述**:
神像的回复和其本身身份目前不符。不同神明应该有不同的回复风格和内容，但当前实现可能没有正确区分。

**影响范围**:
- 神明对话系统
- 玩家沉浸感
- 游戏叙事一致性

**相关文件**:
- `scripts/ai/dialogue_ai_gateway.gd`
- `scripts/core/narrative_generator.gd`
- `scripts/dungeon/dungeon_run.gd` (对话处理部分)

**可能原因**:
- AI提示词没有充分强调神明身份
- 神明配置信息没有正确传递给生成系统
- 本地叙事生成器没有根据神明ID区分回复风格

**待调查**:
- [ ] 检查god_cfg是否正确传递给AI gateway
- [ ] 检查AI prompt是否包含神明身份信息
- [ ] 检查本地narrative_generator是否根据god_id生成不同风格
- [ ] 测试不同神明的回复差异

---

## Fixed Bugs

### [BUG-000] 与神像交互后玩家自动移动
**状态**: 已修复 ✓
**优先级**: 高
**发现时间**: 2026-03-10
**修复时间**: 2026-03-10
**修复提交**: 54ef232

**描述**:
玩家与神像交互的第一次对话后，玩家会自动朝一个方向移动很长一段距离，对话还没结束。

**原因**:
1. 输入锁定释放太快（仅0.1秒grace period）
2. 祷告面板可见时没有阻止玩家移动

**修复方案**:
1. 将INPUT_UNLOCK_GRACE_PERIOD从0.1秒增加到0.5秒
2. 在_is_game_input_locked()中添加_prayer_panel.visible检查

**相关文件**:
- `scripts/dungeon/dungeon_run.gd:143` (grace period常量)
- `scripts/dungeon/dungeon_run.gd:2237` (输入锁定逻辑)
