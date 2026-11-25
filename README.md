# DeepSeek Harness · Windows → Linux 迁移包

把 Windows 版 **DeepSeek Harness（DSH）** 的插件与个性化设置，迁移到 Linux 上的 DSH。

仓库：<https://github.com/wwumingxu/deepseek->

> ⚠️ 仓库目前是 **私有** 的。在 Linux 上 clone 前需要先登录 GitHub
> （`gh auth login`，或使用 PAT：`git clone https://<token>@github.com/wwumingxu/deepseek-.git`）。
> 想免登录直接 clone，可在仓库 Settings → Danger Zone 里改为 Public。

- 源环境：Windows 桌面版 DSH `0.2.2-rc.5`，profile 名为 `desktop`
- 目标环境：Linux 上的 DSH（命令行 `dsh` 或桌面版均可）
- 配置已剔除密钥与本机路径，**不含任何 API Key / 登录凭据**

---

## 一、迁移了什么

| 内容 | 是否迁移 | 说明 |
| --- | --- | --- |
| 插件清单与版本（12 个 bundle） | ✅ | 见 [插件清单](#五插件清单) |
| `cordis.patch.yml` 个性化设置 | ✅ | 默认模型、UI、GPT 中转 provider 等 |
| `pnpm-workspace.yaml` | ✅ | `nodeLinker: hoisted` 与构建脚本白名单 |
| `cordis.yml` | ✅ | profile 根模板（空列表） |
| `node_modules/` | ❌ | Windows 二进制，Linux 上由 pnpm 重新安装 |
| `pnpm-lock.yaml` | ❌ | 含已移除的 Windows 专用包，安装时重新生成 |
| `.credentials.yaml`、API Key | ❌ | 敏感信息，不上传；Linux 上重新登录/配置 |
| 会话记录、附件、工作区列表 | ❌ | 含 Windows 绝对路径，迁移会失效 |
| `dsh-sync` 实例 ID、隧道设备注册 | ❌ | 与机器绑定，新机器重新生成 |
| `dsh-computer-use-win` | ❌ | **仅支持 win32**，Linux 无法安装（见第五节替代方案） |

> 迁移的是「配置」，不是「运行环境」。Linux 上 DSH 本体、插件依赖都需要重新安装一次。

> 如果你打算让 Linux 上的 DSH Agent 自己完成安装，直接把仓库地址丢给它，并让它先读
> [`AGENT-INSTALL.md`](AGENT-INSTALL.md)（一份面向 Agent 的短说明书，含硬约束与验证步骤）。

---

## 二、前置要求

| 依赖 | 版本要求 | 检查命令 |
| --- | --- | --- |
| Node.js | **>= 24.9.0**（DSH 的硬性要求） | `node -v` |
| pnpm | 任意较新版本（`dsh plugin` 依赖它） | `pnpm -v` |
| dsh | 建议 >= 0.2.2-rc.5 | `dsh --version` |
| git | 任意 | `git --version` |

**1. 安装 Node.js 24+**（任选其一）

```bash
# 方式 A：nvm（推荐，便于切换版本）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 24 && nvm use 24

# 方式 B：发行版仓库 / NodeSource
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
```

**2. 安装 pnpm**

```bash
npm install -g pnpm
# 或者
corepack enable && corepack prepare pnpm@latest --activate
```

**3. 安装 DSH 命令行**

```bash
npm install -g @deepseek-ai/dsh
dsh --version
```

> 已有 Linux 桌面版的用户可跳过第 3 步，见[第四节](#四linux-桌面版用户)。

---

## 三、快速开始（命令行 / Web 版，推荐）

```bash
git clone https://github.com/wwumingxu/deepseek-.git dsh-linux-profile
cd dsh-linux-profile

# 预览将要执行的操作（不写文件）
bash install.sh --dry-run

# 正式安装：默认写入 web profile
bash install.sh

# 启动
dsh web
```

`install.sh` 默认安装到 `~/.dsh/profiles/web`，启动后浏览器打开 `dsh web` 输出的地址即可。

### 脚本做了什么

1. 检查 `dsh` / `node` / `pnpm` 是否可用，并在 Node < 24.9 时告警；
2. 把目标 profile 的现有配置备份到 `.migration-backup-<时间戳>/`；
3. 写入 `package.json`（12 个 bundle）、`cordis.patch.yml`、`cordis.yml`、`pnpm-workspace.yaml`；
4. 删除旧的 `pnpm-lock.yaml`，执行 `dsh plugin --profile web install`（内部调用 pnpm）；
5. 用 `dsh --profile web --dump-config` 校验配置树能否正确组合。

### 常用参数

```bash
bash install.sh --profile web          # 指定 profile（默认 web）
bash install.sh --dsh-home /data/.dsh  # 自定义 DSH_HOME
bash install.sh --no-install           # 只写配置，不装依赖
bash install.sh -y                     # 跳过确认
bash install.sh --dry-run              # 只打印计划
```

---

## 四、Linux 桌面版用户

桌面版使用保留 profile `desktop`，且**必须由桌面版应用初始化**。

```bash
# 1. 先启动一次 Linux 桌面版 DSH，等它把 ~/.dsh/profiles/desktop 建好，然后完全退出
# 2. 确认桌面版自带的 dsh 命令可用
dsh --version

# 3. 迁移到 desktop profile
bash install.sh --profile desktop
```

如果终端里没有 `dsh` 命令（桌面版未把 CLI 暴露到 PATH），先找一下桌面版自带的那个：

```bash
sudo find / -path '*resources/runtime/cli/bin/dsh' -type f 2>/dev/null
```

找到后可以直接用绝对路径执行，或临时加进 PATH：

```bash
export DSH_CLI="/opt/DeepSeek Harness/resources/runtime/cli/bin/dsh"   # 换成上一步的路径
"$DSH_CLI" --version
"$DSH_CLI" plugin --profile desktop install
```

实在找不到，就只写配置，再到界面里手动装插件：

```bash
# 只写配置，不执行安装
bash install.sh --profile desktop --no-install
```

然后打开桌面版 → **设置 → 插件**，按[第五节](#五插件清单)的清单安装 12 个插件（版本号保持一致）。配置文件已在 `~/.dsh/profiles/desktop/` 下就位，插件装完后重启应用即生效。

> 桌面版运行时无法从外部改写它的 profile，安装/回滚前请**完全退出** DSH 桌面版。

---

## 五、插件清单

| # | 插件 | 版本 | 作用 |
| --- | --- | --- | --- |
| 1 | `@deepseek-ai/dsh-base` | 随 DSH | 基础 bundle（内置） |
| 2 | `@deepseek-ai/dsh-web-app` | 随 DSH | Web GUI bundle（内置） |
| 3 | `dshmarket` | 1.73.19 | 插件市场 |
| 4 | `@vectorize-io/hindsight-coding-agents` | 0.8.7 | Hindsight 代码记忆 |
| 5 | `@liustack/modlens` | 3.27.3 | 图片/视觉桥（截图理解） |
| 6 | `@linxin666/dsh-remote-web-ui` | 0.4.18 | 远程 Web UI、局域网访问、内网穿透 |
| 7 | `@linxin666/dsh-client-ui-skill-explorer` | 0.4.18 | 技能浏览器 |
| 8 | `dsh-better-sidebar` | 0.32.1 | 侧边栏增强 |
| 9 | `@linxin666/dsh-ssh` | 0.4.18 | SSH 主机管理与远程执行 |
| 10 | `@weibaohui/dsh-sync` | 0.4.11 | 配置云同步 |
| 11 | `billion-context` | 0.1.216 | 上下文压缩 |
| 12 | `@dougen/dsh-deepseek-usage` | 0.20.0 | DeepSeek 用量统计 |

**关于 `dsh-computer-use-win`**

原 Windows 配置中的 `dsh-computer-use-win@0.5.7` 声明了 `os: ["win32"]`，在 Linux 上**无法安装**，因此已从本仓库移除。若需要桌面自动化能力，可自行安装跨平台版本：

```bash
dsh plugin --profile web add dsh-computer-use@0.3.1
```

（该包为第三方实现，未包含在本迁移包中，请自行评估。）

---

## 六、安装后要做的事

**1. 重新登录 DeepSeek 账号**

凭据不随仓库迁移。启动 `dsh web` 后，在界面里按提示用设备码登录（`deepseek-account` provider）。

**2. 配置 GPT 中转 Key（可选）**

`cordis.patch.yml` 里的 `llm-pi-ai` provider 通过环境变量读取密钥：

```yaml
providers:
  gpt:
    apiKeyEnv: GPT_API_KEY
    baseURL: https://api.ai-pixel.online/v1
```

设置后重启 DSH：

```bash
export GPT_API_KEY=sk-你的key
dsh web
# 想持久化就写进 ~/.bashrc 或 ~/.profile
```

不配置也不影响启动，只是 `gpt-*` 模型不可用。

**3. 局域网 / 隧道（注意）**

`remote-web-ui` 当前配置为：

```yaml
lanBind: true      # 监听局域网
autoTunnel: true   # 自动建立公网隧道
```

这会把 Web UI 暴露到局域网，并自动开启公网隧道。不需要的话，编辑
`~/.dsh/profiles/<profile>/cordis.patch.yml`，把对应值改为 `false` 后重启。

---

## 七、目录结构

```text
.
├── install.sh                    # 一键安装
├── rollback.sh                   # 一键回滚
├── AGENT-INSTALL.md              # 交给 Linux 上 DSH Agent 执行的说明书
├── profile/                      # 从 Windows 导出的配置（可直接对照修改）
│   ├── package.json              # 插件依赖 + bundle 顺序
│   ├── cordis.patch.yml          # 个性化设置
│   ├── cordis.yml                # profile 根模板
│   └── pnpm-workspace.yaml       # pnpm 配置
├── docs/
│   ├── PLUGINS.md                # 插件详解
│   └── TROUBLESHOOTING.md        # 常见问题
└── scripts/
    └── export-from-windows.ps1   # 在 Windows 上重新导出配置
```

---

## 八、回滚

```bash
bash rollback.sh --profile web            # 还原最近一次备份
bash rollback.sh --profile web --list     # 查看所有备份
bash rollback.sh --profile web --backup .migration-backup-20261125-113000
```

回滚会还原安装前的 `package.json` / `cordis.patch.yml` 等文件，并重新安装依赖。

---

## 九、安全说明

- 仓库内**没有** `.credentials.yaml`、API Key、登录 token、会话记录。
- `cordis.patch.yml` 只引用环境变量名 `GPT_API_KEY`，不含密钥本身。
- 迁移脚本只读写 `$DSH_HOME/profiles/<profile>/`，不改动 DSH 安装目录。
- 所有改动前都会备份，可随时 `rollback.sh` 还原。

---

## 十、以后如何更新这个仓库

在 Windows 机器上（配置有变动后）执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-from-windows.ps1
```

脚本会读取当前 `desktop` profile，自动剔除 Windows 专用插件与敏感文件，重新生成 `profile/` 下的四个配置文件。然后提交推送即可：

```bash
git add -A && git commit -m "sync from windows" && git push
```

---

## 十一、常见问题

见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)，覆盖：Node 版本不符、pnpm 缺失、插件安装失败、构建脚本被拦截、插件与 DSH 版本不兼容、desktop profile 被占用、端口/隧道问题等。
