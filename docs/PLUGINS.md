# 插件详解

本仓库迁移的 12 个 bundle（按 `package.json` 中 `dsh.profile.bundles` 的加载顺序）。

DSH 的 profile 由若干「bundle」层层叠加而成：每个 bundle 自带一份配置层，最后由
`cordis.patch.yml` 覆盖。**bundle 的顺序会影响最终配置**，新增插件时请追加到列表末尾
（除非该插件需要排在特定插件之前）。

| 顺序 | 包名 | 版本 | 平台 | 作用 / 备注 |
| --- | --- | --- | --- | --- |
| 1 | `@deepseek-ai/dsh-base` | 随 DSH | 全平台 | 内核、工具、会话、agent 基础能力。DSH 必需 |
| 2 | `@deepseek-ai/dsh-web-app` | 随 DSH | 全平台 | Web GUI 外壳与内置设置页。`dsh web` 必需 |
| 3 | `dshmarket` | 1.73.19 | 全平台 | 插件市场 UI，可在界面里搜索/安装/更新插件 |
| 4 | `@vectorize-io/hindsight-coding-agents` | 0.8.7 | 全平台 | Hindsight 项目记忆（🧠 页面、检索、会话沉淀） |
| 5 | `@liustack/modlens` | 3.27.3 | 全平台 | 视觉桥：把图片/截图交给视觉模型读取 |
| 6 | `@linxin666/dsh-remote-web-ui` | 0.4.18 | 全平台 | 远程 Web UI：局域网访问 + 自动公网隧道 |
| 7 | `@linxin666/dsh-client-ui-skill-explorer` | 0.4.18 | 全平台 | 技能（skill）浏览与查看面板 |
| 8 | `dsh-better-sidebar` | 0.32.1 | 全平台 | 侧边栏增强：会话分组、折叠等 |
| 9 | `@linxin666/dsh-ssh` | 0.4.18 | 全平台 | SSH 主机管理与远程命令执行 |
| 10 | `@weibaohui/dsh-sync` | 0.4.11 | 全平台 | 配置/数据云同步 |
| 11 | `billion-context` | 0.1.216 | 全平台 | 上下文压缩与折叠（长会话管理） |
| 12 | `@dougen/dsh-deepseek-usage` | 0.20.0 | 全平台 | DeepSeek 用量/额度统计 |

## 平台差异

| 包 | 说明 |
| --- | --- |
| `dsh-computer-use-win@0.5.7` | **已移除**。`package.json` 中声明 `os: ["win32"]`，Linux 上 pnpm 会直接拒绝安装。 |
| `dsh-computer-use@0.3.1` | 可选的跨平台替代（未包含在本仓库）。安装：`dsh plugin --profile web add dsh-computer-use@0.3.1` |

## 原生依赖 / 构建脚本

以下依赖包含原生模块或需要下载二进制，`pnpm-workspace.yaml` 已通过 `allowBuilds` 放行：

| 依赖 | 用途 | 由谁引入 |
| --- | --- | --- |
| `cloudflared` | 内网穿透隧道二进制 | `@linxin666/dsh-remote-web-ui` |
| `ssh2` / `cpu-features` | SSH 实现及其原生加速 | `@linxin666/dsh-ssh` |

如果安装日志出现 `Ignored build scripts`，说明 `allowBuilds` 未生效，见
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#4-安装日志出现-ignored-build-scripts)。

## 增删插件

不要手工编辑 `package.json` 的依赖列表——用 `dsh plugin` 让它同时维护依赖和 bundle 顺序：

```bash
# 新增
dsh plugin --profile web add <包名>@<版本>

# 移除
dsh plugin --profile web remove <包名>

# 查看当前已安装
dsh plugin --profile web list
```

改完后重启 DSH 生效。如果想把改动同步回本仓库，在 Windows 上运行
`scripts/export-from-windows.ps1` 重新导出。
