# VerbatimFlow

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-orange.svg)](#状态)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-blue.svg)](#)

一款快速、零改写的 macOS 语音输入工具 —— 你说的话，原封不动。

> **延伸阅读：** 想自己构建 AI 工具？查看 [Agent Skills 资源库](https://www.axtonliu.ai/agent-skills)（含幻灯片、PDF、诊断工具）

<p align="center">
  <img src="assets/bento-features.png" alt="VerbatimFlow 功能总览" width="720">
</p>

## 为什么自己做

我试了几款 Mac 上主流的语音输入工具，它们都有同样的问题：

- **改你的原话。** 你说 A，它输出 B。擅自润色、改写，让你对自己的输入失去信任。
- **按键卡住不释放。** 你已经松手了，它还在录。只能再按一次，或者重启。
- **把你的话当问题回答。** AI 输入法的通病：你在打字，它把你的话当成提问，直接生成一段回答塞进输入框。
- **数据去了哪里你不知道。** 闭源黑箱，音频发给了谁、存在哪，完全不透明。

VerbatimFlow 的存在就是因为：我想要一个**能信任**的语音输入工具 —— 说什么打什么、松手就停、不替你做主、代码全部透明。

## 它做什么

VerbatimFlow 是一个 macOS 菜单栏语音输入工具，转写语音后直接注入到当前活跃的应用中。

**核心原则：** 先忠实转写，整理可选、受控。

- **按住说话** — 按住热键录音，松开即转写并注入文本
- **两种模式** — `Standard`（忠实转写 + 基于规则的格式化：标点、空格、大小写）和 `Clarify`（LLM 驱动的精简改写，主动选择才生效）
- **多引擎支持** — Apple Speech、本地 Whisper、OpenAI 云端、Qwen3 ASR（本地，Apple Silicon）
- **即时注入** — 通过 Accessibility API 直接在活跃 App 中插入文本
- **一键撤回** — 回滚上一次插入的转写结果
- **完全开源** — 每一行代码可读；你的音频，你做主

## 状态

> **状态：Alpha**
>
> - 这是一个我每天在用的可用原型，但仍有粗糙之处。
> - 我的主要目标是展示语音输入如何在不过度编辑的前提下工作，而非长期维护此代码库。
> - 如果遇到问题，请提交可复现的 case（输入 + 输出 + 复现步骤）。

## 功能特性

### 工程验收标准（不是演示标准）

我们没有追求"功能最多"，而是定义了"先可用再优化"的门槛：

| 验收项 | 说明 |
|--------|------|
| **全局热键稳定** | 按住录，松开转写，不卡状态。双信号 watchdog + handshake 机制防"伪按下" |
| **权限稳定** | 固定 bundle ID 签名，重启后不频繁重新授权 |
| **插入稳定** | AX → Cmd+V → Unicode typing 三级回落，Terminal / Codex / 标准编辑器都能上屏 |
| **引擎可切换** | Apple Speech / Whisper (tiny–large-v3) / OpenAI Cloud (gpt-4o-mini-transcribe, whisper-1) / Qwen3 ASR (0.6B / 1.7B，Apple Silicon 本地) |
| **失败可恢复** | 转写失败自动保存录音，菜单一键重试，不丢内容 |
| **设置可持久化** | 热键、模式、引擎、模型、语言等核心配置重启保留 |

### 完整功能列表

- **菜单栏应用** — 以 V 形图标驻留在 macOS 菜单栏，实时状态徽标（● 录音中、○ 处理中、— 已暂停）
- **双热键** — 主热键使用当前模式；副热键（`Cmd+Shift+Space`）临时强制 Clarify 模式，仅作用一次
- **热键预设切换** — 支持 `Ctrl+Shift+Space` / `Option+Space` / `Fn`，菜单内切换无需重启
- **多引擎运行时切换** — Apple Speech / Whisper / OpenAI 云端 / Qwen3 ASR，菜单内一键切换
- **Whisper 模型选择** — tiny / base / small / medium / large-v3
- **Clarify 整理** — 支持 OpenAI 和 OpenRouter 双通道，独立配置 provider、model、API key
- **术语词典** — 自定义纠正规则（单词纠正 + `source => target` 替换）
- **中英混合增强** — 专门的混合语言后处理优化
- **语言选择** — System Default / zh-Hans / zh-Hant / en-US
- **转写历史** — 菜单内查看最近转写，支持 Copy + 撤回上次插入
- **失败录音重试** — 转写失败时音频自动持久化，一键重试
- **权限诊断** — 内置权限快照报告、一键跳转系统设置
- **运行时日志** — 完整的可观测日志系统
- **确定性代码签名** — 固定 bundle ID 防止每次构建后权限失效
- **DMG 安装包** — 支持拖放安装到 Applications

## 安装

### 方式一：下载安装包（推荐）

从 [GitHub Releases](https://github.com/axtonliu/verbatim-flow/releases) 下载最新的 `.dmg` 文件，拖放安装到 Applications。

### 方式二：从源码构建

**前置要求：**
- macOS 14+（推荐 Sonoma 及以上）
- Xcode 16+
- 麦克风和辅助功能权限
- Apple Silicon（M1/M2/M3/M4）或 Intel Mac（支持 Universal Binary）

```bash
git clone https://github.com/axtonliu/verbatim-flow.git
cd verbatim-flow

# 构建 .app
./scripts/build-native-app.sh
open "apps/mac-client/dist/VerbatimFlow.app"

# 或构建安装 DMG
./scripts/build-installer-dmg.sh
open "apps/mac-client/dist/VerbatimFlow-installer.dmg"
```

## 使用方法

1. **启动** — 双击 `VerbatimFlow.app` 或运行 `./scripts/run-native-mac-client.sh`
2. **授予权限** — 首次启动会提示授权麦克风、辅助功能、语音识别（也可通过菜单手动请求）
3. **按住热键** — 默认 `Ctrl+Shift+Space` 录音；松开后自动转写并注入
4. **切换模式** — 通过 Settings 菜单在 Standard / Clarify 间切换
5. **临时 Clarify** — 按 `Cmd+Shift+Space` 当前片段强制使用 Clarify 模式

## 配置

### OpenAI / OpenRouter 设置

云端转写和 Clarify 整理通过 `~/Library/Application Support/VerbatimFlow/openai.env` 配置：

```bash
# OpenAI 转写
OPENAI_API_KEY=sk-...
VERBATIMFLOW_OPENAI_MODEL=gpt-4o-mini-transcribe

# 自动路由（先快后准：命中中英混合/术语风险时自动二次识别）
VERBATIMFLOW_OPENAI_AUTO_ROUTE=1
VERBATIMFLOW_OPENAI_AUTO_SECONDARY_MODEL=whisper-1
# 可选调参：
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_ZH_ONLY=1
# VERBATIMFLOW_OPENAI_LANGUAGE_HINT_MODE=auto
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_RISK_SCORE=2
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_PRIMARY_CHARS=8

# Clarify provider: openai 或 openrouter
VERBATIMFLOW_CLARIFY_PROVIDER=openai
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=gpt-4o-mini

# OpenRouter 替代方案
# VERBATIMFLOW_CLARIFY_PROVIDER=openrouter
# OPENROUTER_API_KEY=...
# VERBATIMFLOW_OPENAI_CLARIFY_MODEL=openai/gpt-4o-mini
```

也可通过菜单栏直接编辑：**Settings → Open Cloud Settings**。

### 术语词典

自定义纠正规则位于 `~/Library/Application Support/VerbatimFlow/terminology.txt`：

```
# 术语纠正
VerbatimFlow
macOS
OpenAI

# 替换规则（source => target）
verbal flow => VerbatimFlow
mac OS => macOS
```

### 运行日志

```bash
~/Library/Logs/VerbatimFlow/runtime.log
```

## 项目结构

```
verbatim-flow/
├── apps/mac-client/
│   ├── Sources/VerbatimFlow/    # 原生 Swift 应用
│   │   ├── main.swift           # 入口
│   │   ├── MenuBarApp.swift     # 菜单栏 UI
│   │   ├── AppController.swift  # 核心编排
│   │   ├── HotkeyMonitor.swift  # 全局热键处理
│   │   ├── SpeechTranscriber.swift
│   │   ├── TextInjector.swift   # 基于 Accessibility 的文本注入
│   │   ├── TextGuard.swift      # Format-only diff 守卫
│   │   ├── ClarifyRewriter.swift
│   │   ├── TerminologyDictionary.swift
│   │   └── ...
│   ├── Tests/VerbatimFlowTests/ # 单元测试
│   ├── python/                  # Python ASR 脚本
│   │   ├── scripts/             # CLI 入口（transcribe_qwen.py）
│   │   └── verbatim_flow/       # Qwen3 ASR 转写模块
│   ├── Package.swift
│   └── dist/                    # 构建产物（.app, .dmg）
├── packages/                    # 共享包占位
├── scripts/
│   ├── build-native-app.sh      # 构建 .app
│   ├── build-installer-dmg.sh   # 构建安装 DMG
│   ├── restart-native-app.sh    # 杀进程 + 重启
│   ├── collect-permission-diagnostics.sh
│   └── ...
├── docs/
│   └── ARCHITECTURE.md
├── LICENSE
├── README.md
└── README_CN.md
```

## 常见问题

### 权限问题

- **麦克风不工作：** 系统设置 → 隐私与安全性 → 麦克风 → 确保 VerbatimFlow 已勾选。或使用菜单：**Settings → Request Microphone Permission**。
- **文本不注入：** 系统设置 → 隐私与安全性 → 辅助功能 → 添加 VerbatimFlow。应用使用固定 bundle ID（`com.verbatimflow.app`），权限在重新构建后仍然有效。
- **权限看起来授予了但仍然失败：** 尝试删除后重新添加。运行 `./scripts/collect-permission-diagnostics.sh 30` 获取详细诊断。

### 热键问题

- **热键无响应：** 检查是否有其他 App 占用了相同快捷键。尝试通过 Settings 菜单切换到其他预设。
- **菜单栏图标显示暂停横线：** 热键监听已暂停，点击菜单中的 **Resume Listening**。

### Clarify 模式

- **Clarify 返回原文：** 检查 `openai.env` 中的 API key。查看 `~/Library/Logs/VerbatimFlow/runtime.log` 中的错误信息。
- **想用 OpenRouter：** 在 `openai.env` 中设置 `VERBATIMFLOW_CLARIFY_PROVIDER=openrouter` 并提供 `OPENROUTER_API_KEY`。

## 路线图

- [x] 原生 Swift 路径集成 Whisper 引擎
- [x] 中英混合识别优化
- [x] Qwen3 ASR 本地引擎（0.6B / 1.7B，Apple Silicon）
- [x] 繁体中文（zh-Hant）语言选项
- [x] Universal Binary（Intel + Apple Silicon）
- [ ] 流式转写（边说边出字）
- [ ] 可配置的 text guard 灵敏度阈值
- [ ] 按应用自定义模式 profile

## 贡献

欢迎贡献（低维护项目）：

- 可复现的 bug 报告（输入 + 输出 + 步骤 + 环境）
- 文档改进
- 小型 PR（修复/文档）

> **注意：** 由于维护精力有限，功能请求可能不会被响应。

## 致谢

- [Apple Speech Framework](https://developer.apple.com/documentation/speech) — 设备端语音识别
- [OpenAI Whisper](https://openai.com/research/whisper) — 开源 ASR 模型
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — 基于 CTranslate2 的 Whisper 推理（Python MVP）
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) — 阿里 Qwen 团队的多语言 ASR 模型
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) — Apple Silicon 优化的音频 ML 框架
- [OpenCC](https://github.com/BYVoid/OpenCC) — 简繁中文转换

## 许可证

MIT License — 详见 [LICENSE](LICENSE)。

---

## 作者

**Axton Liu** — AI 教育者 & 创作者

- 网站：[axtonliu.ai](https://www.axtonliu.ai)
- YouTube：[@AxtonLiu](https://youtube.com/@AxtonLiu)
- Twitter/X：[@axtonliu](https://twitter.com/axtonliu)

### 了解更多

- [Agent Skills 资源库](https://www.axtonliu.ai/agent-skills) — 幻灯片、PDF 指南、诊断工具
- [AI 精英周刊 Newsletter](https://www.axtonliu.ai/newsletters/ai-2) — 每周 AI 洞察
- [免费 AI 课程](https://www.axtonliu.ai/axton-free-course) — 开始你的 AI 之旅

---

© AXTONLIU™ & AI 精英学院™ 版权所有
