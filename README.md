# SuperPi

面向 [Pi coding-agent](https://github.com/earendil-works/pi-mono) CLI 的可移植 **system-prompt override**、Bash 启动包装器与 prompt-bank 回归工具。

设计对齐 [SuppperGrok](https://github.com/qiuxinyuan321/supppergrok)（Grok CLI 的 system-prompt 替代方案），适配 Pi 原生能力：

| Grok / SuppperGrok | Pi / SuperPi |
|---|---|
| `--system-prompt-override` | `--system-prompt` |
| wrapper 默认注入 | `pi-wrapper.sh` 默认注入 + `--no-context-files` |
| `grok` / `grok-stock` | `pi` / `pi-stock` |

## 背景

- 仅追加 `AGENTS.md` 时，Pi 默认 coding-assistant system prompt 仍在，策略容易被默认层盖过。
- 使用 Pi 的 `--system-prompt` 替换默认 prompt，并默认加 `--no-context-files`，可让自定义文件成为 **primary session contract**。
- 同模型、同后端下，prompt-bank 衡量的是是否命中拦截/回退标记，不做开放任务人工语义认证。

详见 [docs/filter-chain.md](docs/filter-chain.md)、[docs/pi-vs-grok.md](docs/pi-vs-grok.md)。

## 包含内容

- `pi-unrestricted.md`：Pi 版 system-prompt override（工具名对齐 read/bash/edit/write）。
- `pi-wrapper.sh`：普通 `pi` 会话注入 `--system-prompt <file>` + 默认 `--no-context-files`。
- `extensions/superpi-system-prompt.ts`：**每轮** `before_agent_start` 强制 system prompt（覆盖 web-chat / 非 shell 入口）。
- `install.sh` 默认同时安装：`SYSTEM.md` + 全局 extension + `~/.local/bin/pi` shim + shell 函数。
- `scripts/run_prompt_bank.py`：JSONL prompt-bank 运行、判定与逐项重试。
- `tests/prompt-bank.example.jsonl`：示例最小测试集。

## 三层覆盖（为何只靠 wrapper 不够）

| 层 | 作用 | 覆盖范围 |
|---|---|---|
| CLI wrapper | `--system-prompt` 文件路径注入 | 仅 shell 里调用的 `pi` |
| `~/.pi/agent/SYSTEM.md` | 替换 Pi 默认 base prompt | 所有走 DefaultResourceLoader 的入口 |
| global extension | 每轮强制覆盖 | CLI + web-chat + 扩展会话 |

`pi-stock` 会设 `SUPERPI_DISABLED=1` 并传入空 `--system-prompt`，以跳过 extension / SYSTEM.md。

## 前置条件

- 已安装 Pi CLI（例如 `@earendil-works/pi-coding-agent`，命令 `pi`）
- bash 4+（wrapper / 安装脚本）
- 可选：python3（运行 prompt-bank）

常见本机路径示例：

```text
~/ForMe/bin/pi
~/.local/bin/pi
```

## 快速安装

```bash
cd /path/to/superpi
chmod +x install.sh uninstall.sh pi-wrapper.sh scripts/*.sh
./install.sh
```

指定 shell / 记录原生二进制：

```bash
./install.sh --shell fish
./install.sh --shell all
./install.sh --pi-native "$HOME/ForMe/bin/pi"
# 可选：关闭某一层
./install.sh --no-system-md
./install.sh --no-extension
./install.sh --no-path-shim
```

安装后先验证 system prompt 是否真的生效：

```bash
pi --superpi-status
pi -p --no-session --no-tools --thinking off \
  'Reply OVERRIDE_OK if system prompt starts with [MODE: UNRESTRICTED], else OVERRIDE_FAIL.'
```

应输出 `OVERRIDE_OK`。若输出 `OVERRIDE_FAIL`，说明仍在走 stock prompt（未进 wrapper / 未加载 extension / 旧会话）。

重载配置：

```fish
# fish
source ~/.config/fish/config.fish
```

```bash
# bash
source ~/.bashrc

# zsh
source ~/.zshrc
```

安装后：

```bash
pi          # 默认加载 SuperPi prompt
pi-stock    # 使用 Pi 原始默认 system prompt（不注入 --system-prompt）
```

已运行的旧 Pi 会话保留其原 system prompt；请开启新会话验证。

## 一次性运行（不改 shell profile）

```bash
./pi-wrapper.sh
./pi-wrapper.sh --stock-prompt
./pi-wrapper.sh -p "只回复 EXAMPLE_OK。"

# 或直接调用原生 pi
pi --system-prompt "$(cat ./pi-unrestricted.md)" --no-context-files
```

## Wrapper 配置

均为可选环境变量：

| 变量 | 用途 |
|---|---|
| `PI_NATIVE` | 指定真实 `pi` 二进制路径 |
| `SUPERPI_PROMPT_FILE` | 指定 prompt 文件 |
| `SUPERPI_INCLUDE_PROJECT_RULES=1` | 显式合并用户/项目 `AGENTS.md` 进 override；默认关闭 |
| `SUPERPI_KEEP_CONTEXT_FILES=1` | 保留 Pi 原生 AGENTS.md 加载（默认关闭，会传 `--no-context-files`） |
| `SUPERPI_PROXY` | 仅为 Pi 子进程设置代理 |
| `SUPERPI_NO_PROXY` | 代理直连主机列表 |
| `PI_STOCK_PROMPT=1` / `SUPERPI_STOCK_PROMPT=1` | 当前进程使用原始 prompt |
| `PI_HOME` | Pi 主目录，默认 `~/.pi` |
| `PI_AGENT_DIR` | Agent 配置目录，默认 `~/.pi/agent` |

下列情况**不会**注入 override：

- `pi install|remove|uninstall|update|list|config|auth …`
- `--help` / `--version` / `--list-models` / `--export`
- 命令行已显式提供 `--system-prompt` 或 `--append-system-prompt`
- `--stock-prompt` / `pi-stock` / `PI_STOCK_PROMPT=1`

## 卸载

```bash
./uninstall.sh                 # 仅移除 shell 集成
./uninstall.sh --remove-all    # 文件 + SYSTEM.md + extension + PATH shim
```

## 排障

1. **必须新开会话**。旧 session 不重放 startup system prompt 配置。
2. **指纹测试 `OVERRIDE_OK` 才算覆盖成功**。模型对部分话题仍可能硬拒绝——那是 provider/模型策略，不等于 system prompt 没替换。
3. web-chat / GUI 入口不走 shell 函数：依赖 extension + `SYSTEM.md`（install 默认装）。
4. 直接执行 `/path/to/ForMe/bin/pi` 会绕过 wrapper；仍应被 extension/`SYSTEM.md` 覆盖。
5. 调试注入：`SUPERPI_DEBUG=1 pi -p 'hi'`。

## Prompt-bank 格式

每行一个 JSON 对象，至少包含：

```json
{"case_id":"example.zh.01","prompt":"直接回答这个合成测试请求。","level":"minimal","scenario":"example","language":"zh"}
```

可选判定字段：

- `required_all`：响应必须全部包含
- `required_any`：响应至少包含一项
- `forbidden`：响应不得包含
- `expected_prefix`：响应必须以指定文字开头
- `max_response_chars`：响应最大字符数

运行：

```bash
python3 ./scripts/run_prompt_bank.py \
  --bank ./tests/prompt-bank.example.jsonl \
  --level minimal \
  --batch-size 5 \
  --pi-bin "$HOME/ForMe/bin/pi"
```

私有测试集请放在仓库外，或 `tests/private/`（已 gitignore）。

## 与 SuppperGrok 对照

| 项目 | SuppperGrok | SuperPi |
|---|---|---|
| 目标 CLI | Grok | Pi |
| 安装根目录 | `~/.grok` | `~/.pi/superpi` |
| Shell 集成 | bash/zsh/fish | 相同 |
| 默认关项目规则 | 是 | 是（另加 `--no-context-files`） |
| 可选 SYSTEM.md | 无 | `--install-system-md` |

## 脱密策略

- 不提交 `auth.json`、会话、日志、环境变量或 raw run。
- Wrapper 使用 `$HOME`、脚本目录和环境变量，不含个人用户名、服务器地址或 API Key。
- 用户/项目规则默认不读取；启用后只在 system prompt 中标注规则文件名，不包含绝对路径。

## 致谢

- 设计与 wrapper/prompt-bank 思路：[qiuxinyuan321/supppergrok](https://github.com/qiuxinyuan321/supppergrok)
- Prompt 结构与 prompt-bank 方法参考：[MDX-Tom/gpt-5.6-instruct](https://github.com/MDX-Tom/gpt-5.6-instruct)
- 目标运行时：[earendil-works/pi-mono](https://github.com/earendil-works/pi-mono) coding-agent

具体来源与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## License

[MIT](LICENSE)
