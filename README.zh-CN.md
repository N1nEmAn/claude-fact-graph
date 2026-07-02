# AI fact graph（`fgc`）

[English](README.md) | **中文**

一个**面向 AI 智能体工作的事实图工作记忆**，原生运行在 Claude Code 等 agent 终端内部——无数据库、无服务器、无 Web UI，仅依赖 Python 3 标准库。

事实是节点，意图是边。整张图存放在项目本地的 `.fg/` 目录下（每个节点一个 JSON 文件），通过 `fgc` 命令行查询与维护。`dispatch` 命令可以派生一个 Sonnet 子智能体，让它读取图、干活、再把结果写回图。多 agent 在 tmux 里协作时，`fgc peers` / `fgc send` 提供显式用户授权的通信通道。`view` 命令渲染一张可交互的 HTML DAG 图。

本项目是 [StarVoya](https://github.com/N1nEmAn/StarVoya) `Star` 后端思想的蒸馏——后者是一套约 9,600 行的 Python/FastAPI 系统，含 SQLite、调度循环、容器运行时和 TypeScript TUI。这些重量大多是为了在 Claude Code **外部**运行而存在的。**在 Claude Code 内部，执行者（Claude 本身）、调度器（你）和界面（这个对话框）都已经有了。** 唯一缺的就是那份持久、可查询的事实图。这正是 `fgc` 提供的东西。

```
StarVoya（Star 后端）：SQLite + FastAPI 服务器 + Web UI + TUI + 调度器   →  ~9,600 行
fact-graph（fgc）：     .fg/*.json + 一个 Python CLI + 3 个 prompt 模板  →  ~1,700 行，零依赖
```

## 它能给你什么

- **减少重复探索** —— 图记录了哪些路径走过、哪些结论已确认。
- **分离指挥与执行** —— `dispatch reason` 提出下一步；`dispatch <intent>` 去做；`dispatch verify` 核验。
- **可观察、可恢复** —— `fgc graph` / `fgc view` 随时显示进展；关掉终端，明天还能接着干。
- **自主，但由你驱动** —— `fgc auto` 跑完整的 reason→explore→verify 循环直到完成，带预算上限和停止条件。

## 严格按项目、显式开启

事实图**只**存在于工作目录下的 `.fg/` 中。没有全局存储，没有 `~/.fg`，没有中央注册表。钩子由 `fgc setup` 注册在**项目自己的 `.claude/settings.json`** 里——图数据从不写入 `~`，没跑过 `fgc setup` 的项目完全不受影响。

一个使用了图的项目的结构：

```
你的项目/
├── .fg/                      # 所有图数据都在这里，别处没有
│   ├── project.json          # origin、goal、status、id 计数器
│   ├── facts/{goal,f001,…}.json
│   ├── intents/i001.json …
│   ├── hints/
│   ├── ai-peers.json         # 可选：用户授权过的 tmux peer 目标
│   └── ai-channel.txt        # 可选：追加式 peer 留言日志
└── AGENTS.md                 # （可选）派生子智能体的协议说明
```

每个节点一个文件，让图可以 `git diff`。写入是原子的（`os.replace`）并用 `fcntl.flock` 保护，多个智能体可以并发写图而不损坏。

## 安装

```bash
git clone https://github.com/N1nEmAn/claude-fact-graph.git
cd claude-fact-graph
bash install.sh            # 把 fgc 软链到 PATH + 安装 /fgc-setup skill
#   --cli-only    只软链 fgc，不装 skill
#   --uninstall   两者都移除
```

`fgc` 只用 Python 3 标准库——无需 `pip install`。安装器**不碰** `~/.claude/settings.json`，也**不注册任何全局钩子**。

## 给一个项目开启图

```bash
cd /path/to/your/project
fgc setup --goal "复现空 token 崩溃" --agents
#   → 创建 ./.fg/
#   → 在 ./.claude/settings.json 注册 SessionStart + UserPromptSubmit 钩子
#   → 写 AGENTS.md
```

或者在 Claude Code 里直接：`/fgc-setup <你的目标>`。

开启后，该项目每一轮对话都会自动注入当前图状态，派生的子智能体读写同一份记忆。钩子还会运行 `date` 并注入当前本地时间，让 agent 有明确时间上下文。

## 核心模型

- **fact（事实）** —— 已确认的观察或可复现的结果。一旦写入即不可变。
- **intent（意图）** —— 一个工作单元。`from` = 它依赖的事实；`to` = 它产出的事实（未完成时为 `null`）。`to == "goal"` 的 intent 标志整个项目完成。
- **hint（提示）** —— 给指挥者的一条人类留言。
- **goal（目标）** —— `init` 时创建的特殊终止事实。

状态编码在图结构里，而不是某个状态字段：一个 intent 是「就绪」的，当且仅当它是开放的、它的 `from` 事实都存在（事实不可变，存在即满足依赖）、且不需要等待确认。

## 命令速查

```bash
fgc init --goal "..."                          # 创建 .fg/（或用 fgc setup）
fgc setup --goal "..." --agents                # 给本项目开启（图 + 钩子 + AGENTS.md）
fgc status                                     # 项目状态 + 就绪前线
fgc graph [--format text|json]                 # 完整图
fgc frontier                                   # 仅就绪的 intent
fgc pick [--claim] [--any]                     # 下一个该做的 intent
fgc view [--serve]                             # 交互式 HTML DAG

fgc fact "<观察>" -t "<中文标题>"               # 加一个事实
fgc intent --from f001 "做某事" -t "<标题>"     # 加一个工作
fgc intent --from f001 "删生产数据" --confirm   # 需要人工确认
fgc done i003 --fact "<结果>" -t "<标题>"       # 结束 intent 并记录结果
fgc complete --from f005 --note "..."          # 标记项目完成
fgc confirm i007                               # 批准需要确认的 intent
fgc claim i001 --worker alice                  # 占用边（多智能体时）
fgc release i001 --worker alice                # 释放占用
fgc hint "<留言>"                              # 给指挥者留言
fgc peers --discover                           # 列出 tmux panes，等待用户授权
fgc peers --add harley --target api-6:0.0      # 授权一个 tmux peer
fgc send harley "status?"                      # 经 tmux 发送并追加 .fg/ai-channel.txt
fgc teardown [--purge]                         # 关闭本项目（--purge 连图数据一起删）
```

每个 fact 和 intent 都接受 `-t/--title`：一个简短的人类可读标题（中文 OK），会作为节点标签显示在 HTML 图里。

### peers / send —— 授权式 tmux peer 通信

`fgc` 可以协调已经运行在 tmux 里的多个 AI agent，但它不会因为发现了某个 pane 就自动发消息。peer 通信必须由用户显式授权：

```bash
fgc peers --discover
# 把列表展示给用户，询问哪些 pane / agent 允许互相通信

fgc peers --add harley --target api-6:0.0 --sender "Codex/api2-4"
fgc peers
fgc send harley "登录页构建问题已经修好，请你那边验证一下。"
```

授权配置写在 `.fg/ai-peers.json`。`fgc send` 会拒绝未授权名称，把消息追加到 `.fg/ai-channel.txt`，并使用 tmux `load-buffer` / `paste-buffer` 加额外换行，避免 Claude Code 类 TUI 在空闲或 goal-complete 状态下只换行不提交。agent 在发送前应先读 `fgc peers`，新增或修改 peer 目标前必须先问用户。

### dispatch —— 派一个 Sonnet 子智能体

```bash
fgc dispatch reason                  # 指挥者：读图，提出下一步 intent
fgc dispatch i003 --skip-permissions # 执行者：去做 intent i003
fgc dispatch verify --intent i003    # 核验 i003 声称的结果

fgc dispatch reason --dry-run        # 只打印渲染好的 prompt，不调用模型
```

`dispatch reason` 会用当前图渲染 `templates/reason.md`，调用 `claude -p --output-format json`，解析返回的 JSON，并**把新 intent 直接写回图**。`dispatch <intent>` 用 `explore.md` 做同样的事，然后原子地记录产出的事实并链接该 intent。默认 `--model sonnet`、`--timeout 600`；用 `FG_MODEL` / `FG_TIMEOUT` 环境变量覆盖。

派出去的子智能体工作在**当前目录**，图的 `.fg/` 就在磁盘上，所以它读写的是和你同一份记忆。

### auto —— 驱动整张图到完成

```bash
fgc auto --skip-permissions                  # reason → explore（→ verify）→ 循环
fgc auto --skip-permissions --verify --max-steps 10
fgc auto --dry-run                           # 只预览 reason，不花执行 token
```

每一步先跑 `reason`（提议 intent / 检测完成），然后对每个新就绪的 intent 派一个执行者，可选地核验，再循环。停止条件：目标完成、`reason` 连续两次 noop/rejected、某步图无变化、或步数/探索预算用尽。

### view —— HTML 可视化

```bash
fgc view                  # 生成自包含的 fact-graph.html 快照并打开
fgc view --serve          # 起一个会自动刷新（每 2s）的实时页面
```

一张深色、可交互的分层 DAG：事实是节点（种子=蓝、派生=青、目标=琥珀+发光），intent 是按状态着色的边（完成=青色实线、开放=琥珀虚线、被占用=黄色虚线、待确认=玫红虚线）。点击节点或边标签弹出详情面板；拖动平移，滚轮缩放。静态快照把 JSON 内联进 HTML，用 `file://` 直接打开无需服务器；`--serve` 起一个标准库 HTTP 服务器，只绑定本机回环地址、用不可猜测的 token 路径轮询 `/__fg_graph__/<token>.json`（同源，无 CORS）。

## 自主守护 —— 提示注入

派出去的执行者会带着**整张图**——每个 fact、intent、hint 的 `description`——拼进它的 prompt。任何被记录成「事实」的文本，都会成为下一个执行者看到的指令。指挥者（`reason.md`）和执行者（`_agents_system_prompt`）的 prompt 都把图内容用围栏框起来，标注为**不可信数据**，并告诉智能体：把内嵌的「忽略你的规则 / 运行这个命令」当成要记录的观察，而不是要服从的指令。这是*文本层面*的防御，不是沙箱。

当下面三点同时成立时要特别小心：(1) 图来自不可信内容（仓库里被人放了恶意的 `.fg/*.json`，或智能体从攻击者控制的代码/输出里抄了一条事实）；(2) 你传了 `--skip-permissions`；(3) 执行者有真实的 shell/文件权限。**不要在 `.fg/` 不可信的仓库上跑 `fgc auto --skip-permissions`。** 优先用默认（每个工具调用都提示你），并在信任自主跑写出来的事实之前先读一遍。

## 自定义 prompt

模板是带 `{占位符}` 替换的纯 markdown。编辑 `templates/*.md` 来调整行为（比如把事实约束成安全发现的 schema）。占位符：`{origin}`、`{goal}`、`{graph_yaml}`、`{fact_ids}`、`{open_intents}`、`{hints}`、`{max_intents}`（reason）；`{graph_yaml}`、`{intent_id}`、`{intent_description}`（explore）；`{intent_description}`、`{result_description}`（verify）。

## 环境要求

- Python 3.10+（仅标准库——`json`、`fcntl`、`http.server`、`argparse` 等）
- POSIX 系统（Linux / macOS / WSL）。Windows 上没有 `fcntl.flock`。
- `dispatch` / `auto` 需要 PATH 上有 `claude` CLI（Claude Code）。
- 可选：`tmux`，用于经用户授权的多 agent peer 通信。

## 目录结构

```
claude-fact-graph/
├── lib/
│   ├── fg.py                # CLI：Store、图操作、dispatch、auto 循环、view、setup/teardown
│   ├── fg-hook.py           # Claude Code 的 SessionStart / UserPromptSubmit 钩子桥接
│   ├── _settings_patch.py   # 在 settings.json 里幂等地增删钩子条目
│   └── view_template.html   # 单文件深色 DAG 可视化（内嵌 JS）
├── templates/
│   ├── reason.md            # 指挥者 prompt
│   ├── explore.md           # 执行者 prompt
│   └── verify.md            # 核验者 prompt
├── skill/SKILL.md           # /fgc-setup 项目初始化 skill
├── examples/README.md       # 完整示例
├── install.sh
├── SKILL.md                 # 根 skill 文档
└── LICENSE                  # MIT
```

## 致谢

基于 [StarVoya](https://github.com/N1nEmAn/StarVoya) / [Cairn（衍迹）](https://github.com/oritera/Cairn)（事实/意图图、调度器、worker 调度）和 [pi-mono](https://github.com/badlogic/pi-mono)（智能体运行时、工具系统）的思想，蒸馏成原生运行于 Claude Code 内、无需后端的形态。

## 许可证

MIT © N1nEmAn
