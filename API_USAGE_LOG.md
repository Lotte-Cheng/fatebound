# API Usage Log

本文件记录项目中对外部API的使用情况，用于追踪API调用、成本和性能。

## API配置

### OpenAI API
- **配置文件**: `config/ai_config.json`
- **Gateway**: `scripts/ai/dialogue_ai_gateway.gd`
- **使用场景**: 神明对话生成

## 使用记录

### 2026-03-10

#### 神明对话系统测试
- **功能**: 玩家与神像交互对话
- **API调用点**:
  - 意图解析 (Intent Parsing)
  - 叙事生成 (Narrative Generation)
  - 建议生成 (Suggestion Generation)
- **相关代码**: `scripts/dungeon/dungeon_run.gd:1861-1920`
- **备注**:
  - 有本地fallback机制（narrative_generator.gd）
  - 需要追踪API可用性和降级情况

---

## 监控指标

### 需要记录的信息
- [ ] API调用次数（按功能类型）
- [ ] 响应时间
- [ ] 成功/失败率
- [ ] 降级到本地生成的频率
- [ ] Token使用量（如适用）
- [ ] 成本估算

### 建议改进
1. 在dialogue_ai_gateway.gd中添加使用统计
2. 记录每次对话轮次的API调用情况
3. 在游戏结束时输出总体使用报告
4. 考虑添加API使用限制和告警

---

## API错误日志

_记录API调用失败和降级情况_

### 格式
```
日期 | 功能 | 错误类型 | 详情 | 是否降级
```

---

## 成本估算

_根据API定价和使用量估算成本_

### OpenAI API
- **模型**: [待确认]
- **估算方式**: [待实现]
- **月度预算**: [待设定]

---

## 注意事项

1. 确保API密钥安全，不要提交到代码库
2. 实现合理的重试和超时机制
3. 监控API配额使用情况
4. 为玩家提供可选的本地模式（不使用API）
5. 记录warning信息以便调试和优化
