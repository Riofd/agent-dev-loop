---
name: agent-dev-loop
description: >
  Multi-agent collaborative code development loop using model-specialized agents.
  Use when you need to develop a feature/module with adversarial review, I/O clarity,
  and rigorous quality gates. Triggers when users say "用 agent 开发 xxx"、"多 agent
  协作开发"、"自动代码评审流程"、"基于 devdoc 开发"、或要求启动某个具体子功能模块的完整开发流程。
  Supports flexible model assignment per agent role at activation time.
metadata:
  {
    openclaw: {
      emoji: "🤖",
      requires: { anyBins: ["claude", "codex", "gh"] },
    },
  }
---

# Agent Dev Loop

A multi-agent collaborative code development framework that leverages different models'
specialized capabilities through distinct agent roles, with adversarial review loops
and structured documentation.

## 🎯 Core Architecture

| Role | Default Model | Runtime | Responsibility |
|------|--------------|---------|----------------|
| 任务规划 Agent (Task Planner) | deepseek-v4-pro | claude-code | 需求分析 + 任务拆分 |
| 方案评审 Agent (Plan Reviewer) | gpt-5.5 (extra-high) | codex | 对抗评审 + 提出问题 |
| 代码编写 Agent (Coder) | glm-5.1 | claude-code | 单模块实现 |
| 代码评审 Agent A | glm-5.1 | claude-code | 独立评审 |
| 代码评审 Agent B | gpt-5.5 | codex | 独立评审 |
| 代码评审专家 (Review Expert) | deepseek-v4-pro | claude-code | 综合裁定 |

> **模型灵活配置**：上述模型均可通过上下文灵活指定。激活时用户可声明如 "codex 用 gpt-5.5 并启用 extra-high 模式"、"评审专家用 kimi-k2.6" 等。

## 📁 项目结构

在启动时，skill 在 `~/.openclaw/workspace/agent-dev/` 下创建项目目录：

```
agent-dev/
├── scripts/
│   ├── plan_review_loop.sh   # 方案评审循环
│   ├── code_review_loop.sh   # 代码评审循环
│   └── notify_done.sh        # 完成通知
├── sessions/                 # 各 agent session 记录
│   ├── task_planner.session
│   ├── plan_reviewer.session
│   ├── coder.session
│   ├── reviewer_a.session
│   ├── reviewer_b.session
│   └── review_expert.session
└── devdoc/
    └── <name>_devdoc.md      # 开发文档（所有阶段共享）
```

## 🔄 Phase 0: 环境检查 + 项目初始化

**在开始任何开发前，必须执行以下检查：**

```bash
# 1. 检查各 agent 运行时是否可用
which claude && claude --version
which codex && codex --version
gh --version

# 2. 检查模型可用性（ping 各模型 API）
# deepseek-v4-pro: curl https://api.deepseek.com/v1/models
# gpt-5.5: curl https://api.openai.com/v1/models
# glm-5.1: curl https://api.minimax.chat/v1

# 3. 创建/恢复项目目录
PROJECT_DIR="$HOME/.openclaw/workspace/agent-dev/${PROJECT_NAME}"
if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR/scripts" "$PROJECT_DIR/sessions" "$PROJECT_DIR/devdoc"
  echo "# ${PROJECT_NAME} 开发文档" > "$PROJECT_DIR/devdoc/${PROJECT_NAME}_devdoc.md"
fi

# 4. 如果是恢复任务，从 devdoc 读取已完成的模块和当前状态
```

**重要**：devdoc 是 agent 的共享记忆，任何 agent 因模型/网络异常退出后，
都依赖 devdoc 恢复任务状态。确保每次循环结束后将状态写入 devdoc。

## 🔄 Phase 1: 任务规划循环

### Step 1.1: 任务规划 Agent 分析需求

使用 deepseek-v4-pro 模型在 claude-code 中启动任务规划 agent：

```bash
claude --permission-mode bypassPermissions --print \
  --model deepseek/deepseek-v4-pro \
  --dangerously-skip-permissions \
  "## 角色
你是一个高级需求分析和任务规划专家。你的任务是将复杂需求拆分为 IO 清晰、边界明确、易于独立测试的子功能模块。

## 输入
用户需求：${USER_REQUIREMENT}

## 输出要求
1. **需求理解**：用一段话准确描述需求的核心目标
2. **模块拆分**：将需求拆分为 N 个子功能模块，每个模块包含：
   - 模块名称（英文，简短）
   - 输入（I）：明确的输入数据、来源、格式
   - 输出（O）：明确的输出数据、格式、消费者
   - 验收标准：可独立测试的 3-5 条标准
3. **执行顺序**：模块间的依赖关系和推荐执行顺序
4. **关键技术选型**：每个模块推荐的实现技术栈

将以上内容写入 devdoc：${PROJECT_DIR}/devdoc/${PROJECT_NAME}_devdoc.md
格式要求 Markdown，结构清晰。

完成后执行：
openclaw system event --text \"任务规划完成：拆分为 N 个子模块\" --mode now"
```

### Step 1.2: 方案评审循环（对抗评审）

启动 codex gpt-5.5 评审 agent：

```bash
codex exec --full-auto \
  "## 角色
你是一个资深架构评审专家，擅长识别复杂任务规划中的边界不清、依赖混乱、
测试困难等问题。你的评审标准是：子功能模块必须 IO 清晰、边界明确、易于独立测试。

## 待评审内容
读取 devdoc：${PROJECT_DIR}/devdoc/${PROJECT_NAME}_devdoc.md
重点审查：
1. 各子模块的 I/O 定义是否清晰、无歧义
2. 模块间的依赖是否合理、是否可能产生循环依赖
3. 每个模块的验收标准是否可独立测试
4. 是否有遗漏的边界情况或异常处理场景

## 输出格式
对每个问题，输出：
【评审意见 N】模块X / 问题描述 / 严重程度（严重/建议）
对整体方案，给出：合格 / 需要修改

将评审结果追加写入 devdoc 的【方案评审】章节。"
```

### Step 1.3: 对抗回复

将评审意见反馈给任务规划 agent 进行回复和修订：

```bash
claude --permission-mode bypassPermissions --print \
  --model deepseek/deepseek-v4-pro \
  "## 对抗评审回复
方案评审 agent 提出了以下评审意见，请逐一认真思考和回复：

【读取 devdoc 中的评审意见】

## 你的任务
1. 逐条分析评审意见，判断是否合理
2. 对于每条意见，明确回复：接受/不接受 + 理由
3. 接受的意见，说明如何修改方案
4. 不接受的意见，给出反驳理由
5. 修改后的方案写入 devdoc

## 原则
- 保持开放心态，但坚持技术上有充分理由的立场
- 目标是让最终方案真正清晰、可独立测试
- 评审和回复过程体现对抗而非盲从

完成后执行：
openclaw system event --text \"任务规划回复完成，等待下一轮评审\" --mode now"
```

### Step 1.4: 收敛判断

重复 1.2 → 1.3 直到：
- 评审 agent 给出"合格"结论
- 或两个 agent 连续两轮无实质分歧

最终方案写入 devdoc【最终方案】章节。

## 🔄 Phase 2: 代码实现循环

对每个子功能模块，依次执行：

### Step 2.1: 代码编写 Agent 实现模块

使用 glm-5.1 模型，每次只实现一个子功能模块：

```bash
claude --permission-mode bypassPermissions --print \
  --model zai/glm-5 \
  "## 当前任务
实现子功能模块：${MODULE_NAME}

## 项目上下文
读取 devdoc：${PROJECT_DIR}/devdoc/${PROJECT_NAME}_devdoc.md
读取模块详细需求：${PROJECT_DIR}/devdoc/${PROJECT_NAME}_devdoc.md 的【最终方案】章节

## 代码质量要求
1. **算法效率**：避免高量级多重循环，用 numpy/numba/pandas 高效实现
2. **Warning 意识**：不忽视任何 Warning，视为潜在 Bug
3. **异常处理**：避免无意义的 fallback 和空异常处理，只捕获值得捕获的异常
4. **日志规范**：日志精简精准，包含关键路径、输入维度、输出维度、中间状态
5. **代码整洁**：修改时及时去掉废弃逻辑和废弃文件
6. **测试覆盖**：为模块编写测试，涵盖：
   - 逻辑原理验证（单元测试）
   - I/O 验证（边界值、正常值、异常值）
   - 压力测试（大尺寸数据）

## 上下文管理
- 保持上下文 < 100k tokens
- 超过 80k tokens 时主动 compact（总结前段、删除已稳定的内容）
- 每次重新开始模块开发前读取 devdoc 确认状态

## 输出
1. 将实现代码写入 ${PROJECT_DIR}/src/${MODULE_NAME}/ 或适当位置
2. 将测试代码写入 ${PROJECT_DIR}/tests/test_${MODULE_NAME}.py
3. 将 I/O 说明、调用方法追加写入 devdoc
4. 在 devdoc 中记录当前模块开发状态：进行中/已完成

完成后执行：
openclaw system event --text \"模块 ${MODULE_NAME} 实现完成，等待评审\" --mode now"
```

### Step 2.2: 代码评审循环

**并行启动两个独立评审 agent：**

**评审 Agent A（glm-5.1 / claude-code）：**
```bash
claude --permission-mode bypassPermissions --print \
  --model zai/glm-5 \
  "## 角色
你是代码评审专家，精通 Python 高效实现、性能优化、测试设计。
你正在评审由代码编写 agent 完成的模块：${MODULE_NAME}

## 待评审代码
读取：${PROJECT_DIR}/src/${MODULE_NAME}/ 下的代码文件
读取：${PROJECT_DIR}/tests/test_${MODULE_NAME}.py

## 评审维度
1. **算法效率**：是否有高量级循环、是否充分利用 numpy/numba/pandas
2. **Warning 处理**：代码中是否有未处理的 Warning 风险
3. **异常处理**：是否合理、是否有空 except / 过度捕获
4. **日志质量**：是否精简精准、是否记录关键维度信息
5. **测试覆盖**：是否涵盖逻辑、I/O、压力测试
6. **代码整洁**：是否有废弃逻辑残留

## 输出格式
【评审意见】序号 / 文件:行号（如有）/ 问题描述 / 严重程度（必须修复/建议优化）

将评审结果写入：${PROJECT_DIR}/sessions/review_a_${MODULE_NAME}.json
格式：{module, opinions: [{id, file, line, description, severity}]}"
```

**评审 Agent B（gpt-5.5 / codex）：**
```bash
codex exec --full-auto \
  "## 角色
你是代码评审专家，擅长 API 设计、边界情况处理、代码可维护性。
你正在评审由代码编写 agent 完成的模块：${MODULE_NAME}

## 待评审代码
读取：${PROJECT_DIR}/src/${MODULE_NAME}/ 下的代码文件
读取：${PROJECT_DIR}/tests/test_${MODULE_NAME}.py

## 评审维度
1. **I/O 清晰度**：输入输出接口是否定义清晰、类型是否明确
2. **边界处理**：空值、零值、极值的处理是否完备
3. **可维护性**：函数长度、命名、可读性
4. **错误处理**：是否有有意义的错误信息、是否传播而非吞没
5. **测试质量**：测试用例是否覆盖核心逻辑路径

## 输出格式
【评审意见】序号 / 文件:行号（如有）/ 问题描述 / 严重程度（必须修复/建议优化）

将评审结果写入：${PROJECT_DIR}/sessions/review_b_${MODULE_NAME}.json
格式：{module, opinions: [{id, file, line, description, severity}]}"
```

### Step 2.3: 综合评审裁定

deepseek-v4-pro 汇总两个评审意见并裁定：

```bash
claude --permission-mode bypassPermissions --print \
  --model deepseek/deepseek-v4-pro \
  "## 角色
你是代码评审专家，负责综合两个评审 agent 的意见，给出最终裁定。

## 输入
读取评审 A 结果：${PROJECT_DIR}/sessions/review_a_${MODULE_NAME}.json
读取评审 B 结果：${PROJECT_DIR}/sessions/review_b_${MODULE_NAME}.json
读取被评审代码：${PROJECT_DIR}/src/${MODULE_NAME}/

## 任务
1. 合并两个评审意见，去重（相同问题只保留一条）
2. 对每条意见判断：接受/不接受 + 理由
3. 按严重程度排序：必须修复 > 建议优化
4. 给出最终综合评审结论：
   - 通过（无必须修复项）
   - 需要修改（列出必须修复项）
   - 重大问题（架构级问题需打回重做）

## 输出
将综合评审写入：${PROJECT_DIR}/sessions/review_final_${MODULE_NAME}.json
格式：
{
  module,
  total_issues: N,
  must_fix: [...],
  suggestions: [...],
  verdict: "APPROVED" | "NEEDS_REVISION" | "REJECTED"
}

同时追加到 devdoc 的【评审记录】章节。"
```

### Step 2.4: 评审意见回复循环

**如果 verdict = NEEDS_REVISION 或两评审 agent 有异议：**

```bash
# 询问两个评审 agent 对综合意见的看法
# Agent A 回复
claude --permission-mode bypassPermissions --print \
  --model zai/glm-5 \
  "代码评审专家给出了以下综合评审意见：
  读取 ${PROJECT_DIR}/sessions/review_final_${MODULE_NAME}.json

  请你对【必须修复】项逐一回复：
  - 接受：说明如何修改
  - 不接受：说明理由

  将回复写入：${PROJECT_DIR}/sessions/reviewer_a_response_${MODULE_NAME}.json"

# Agent B 回复
codex exec --full-auto \
  "代码评审专家给出了以下综合评审意见：
  读取 ${PROJECT_DIR}/sessions/review_final_${MODULE_NAME}.json

  请你对【必须修复】项逐一回复：
  - 接受：说明如何修改
  - 不接受：说明理由

  将回复写入：${PROJECT_DIR}/sessions/reviewer_b_response_${MODULE_NAME}.json"
```

### Step 2.5: 代码修改

```bash
claude --permission-mode bypassPermissions --print \
  --model zai/glm-5 \
  "## 任务
根据评审意见修改模块 ${MODULE_NAME} 的代码。

## 待处理评审
读取 ${PROJECT_DIR}/sessions/review_final_${MODULE_NAME}.json
读取 ${PROJECT_DIR}/sessions/reviewer_a_response_${MODULE_NAME}.json（如有）
读取 ${PROJECT_DIR}/sessions/reviewer_b_response_${MODULE_MODULE}.json（如有）

## 修改原则
- 严格按照评审意见修改，不要过度修改
- 修改后再次检查是否引入新问题
- 保持代码风格一致

## 输出
修改完成后更新：
1. ${PROJECT_DIR}/src/${MODULE_NAME}/ 下的相关代码
2. 将修改记录写入 devdoc【评审修改记录】

完成后重新进入代码评审循环（Step 2.2）。"
```

**收敛条件**：综合评审 verdict = APPROVED 且两个评审 agent 均无异议。

### Step 2.6: 开发文档记录

模块开发完成后，将以下内容写入 devdoc：

```markdown
## 模块 ${MODULE_NAME} 开发记录

### I/O 说明
- **输入**：数据类型、来源、格式、维度
- **输出**：数据类型、格式、维度、消费者
- **方法入口**：函数签名、关键参数说明

### 调用方法
\`\`\`python
# 示例调用代码
\`\`\`

### 测试用例
| 用例 | 输入 | 预期输出 | 结果 |
|------|------|----------|------|
| 正常值 | ... | ... | ✅ |
| 边界值 | ... | ... | ✅ |
| 压力测试 | ... | ... | ✅ |

### 前后交互逻辑
- 上游依赖：xxx
- 下游消费者：xxx

### 开发状态
- [x] 代码实现
- [x] 评审通过
- [x] 文档完成
```

## 🔄 Phase 3: 模块切换

每完成一个模块：
1. 将最终状态写入 devdoc
2. **开新 session** 开始下一个模块
3. 新 session 读取 devdoc 获取项目上下文和已开发模块

```bash
# 开始新模块前，先确认状态
cat "${PROJECT_DIR}/devdoc/${PROJECT_NAME}_devdoc.md" | grep -E "## 模块" | tail -5
```

## ⚠️ 异常处理与恢复

| 异常场景 | 恢复方式 |
|---------|---------|
| 某 agent 因网络中断退出 | 读取 devdoc 状态，从上一个稳定 checkpoint 重新启动 |
| 评审循环超过 5 轮未收敛 | 由评审专家强制裁定，标记分歧点 |
| 模型 API 不可用 | 降级使用备选模型（如指定了 glm-5.1 可降为 kimi-k2.6） |
| session 上下文超限 | 强制 compact，保留关键决策记录到 devdoc |

## 📝 devdoc 模板结构

```markdown
# ${PROJECT_NAME} 开发文档

## 项目信息
- 创建时间：
- 最后更新：
- 开发阶段：

## 需求概述

## 最终方案（Phase 1 产出）

## 模块列表

## 当前开发模块

## 评审记录

## 开发笔记
```

## 🛠️ 工具脚本

### notify_done.sh
```bash
#!/bin/bash
openclaw system event --text "$1" --mode now
```

## 📌 激活方式

在激活 skill 时，通过上下文明确以下信息（用户提供或从对话推断）：

1. **项目名称**：用于命名 devdoc 和目录
2. **用户需求**：要开发的模块/功能描述
3. **模型配置**（可选）：覆盖默认模型分配
4. **技术栈**（可选）：如 Python/numba、数据库等
