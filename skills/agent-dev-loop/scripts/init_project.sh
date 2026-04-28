#!/bin/bash
# agent-dev-loop 项目初始化脚本
# 用法: ./init_project.sh <project_name> [devdoc_name]

set -e

PROJECT_NAME="${1:-demo}"
DEVICEDOC_NAME="${2:-${PROJECT_NAME}}"
PROJECT_DIR="$HOME/.openclaw/workspace/agent-dev/${PROJECT_NAME}"

echo "📁 初始化项目目录: ${PROJECT_DIR}"

mkdir -p "$PROJECT_DIR"/{scripts,sessions,devdoc,src,tests}

cat > "$PROJECT_DIR/devdoc/${DEVICEDOC_NAME}_devdoc.md" << 'EOF'
# ${PROJECT_NAME} 开发文档

## 项目信息
- 项目名称：
- 创建时间：
- 最后更新：
- 开发阶段：Phase 1 - 任务规划

## 需求概述
（待填写）

## 最终方案（Phase 1 产出）
（待任务规划完成后填写）

## 模块列表
（待任务拆分后填写）

## 当前开发模块
（待开发时填写）

## 评审记录
（待评审完成后填写）

## 开发笔记
（开发过程中记录）
EOF

echo "✅ 项目目录创建完成: ${PROJECT_DIR}"
echo "📝 devdoc: ${PROJECT_DIR}/devdoc/${DEVICEDOC_NAME}_devdoc.md"
