# 常见问题排查

## 1. Node 版本过低

**现象**

```
ERROR: Your Node.js version is not supported
# 或
npm ERR! notsup Required: {"node":">=24.9.0"}
```

**原因**：`@deepseek-ai/dsh` 要求 Node.js >= 24.9.0。

**处理**

```bash
node -v          # 必须 v24.9.0 或更高
nvm install 24   # 用 nvm 的话
nvm use 24
npm install -g @deepseek-ai/dsh
```

注意：`sudo npm i -g` 会把包装到 root 的 Node 环境里，容易出现「版本对不上」。推荐用 nvm 管理，不要用 sudo。

---

## 2. `dsh: command not found`

**原因**：npm 全局 bin 目录不在 `PATH` 里（nvm 用户常见于新开的终端）。

**处理**

```bash
npm config get prefix          # 全局安装位置
echo $PATH | tr ':' '\n' | grep -i node
```

nvm 用户确认 `~/.bashrc` 或 `~/.zshrc` 中有：

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

或者直接重新安装：

```bash
npm install -g @deepseek-ai/dsh
```

---

## 3. `dsh plugin` 报找不到 pnpm

**现象**

```
Error: spawn pnpm ENOENT
```

**原因**：`dsh plugin` 只是把参数转发给 pnpm，pnpm 必须在 `PATH` 中
（或在 DSH 配置里指定 `pnpmCommand`）。

**处理**

```bash
npm install -g pnpm
pnpm -v
```

也可以让 DSH 使用指定路径的 pnpm（写入 profile 的 `package.json` 或用户配置）：

```json
{ "dsh": { "profile": { "pnpmCommand": "/usr/local/bin/pnpm" } } }
```

---

## 4. 安装日志出现 `Ignored build scripts`

**现象**

```
Ignored build scripts: cloudflared, ssh2, cpu-features.
Run "pnpm approve-builds" to pick which dependencies should be allowed to run scripts.
```

**原因**：pnpm 10+ 默认不执行依赖的安装脚本，需要在 `pnpm-workspace.yaml` 里用 `allowBuilds` 显式放行。

**处理**：确认 profile 目录下的 `pnpm-workspace.yaml` 内容为：

```yaml
packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
allowBuilds:
  cloudflared: true
  cpu-features: true
  ssh2: true
```

然后重装：

```bash
dsh plugin --profile web install
```

若仍然被拦截，进入 profile 目录手动重建：

```bash
cd ~/.dsh/profiles/web
pnpm rebuild cloudflared ssh2 cpu-features
```

---

## 5. 插件与 DSH 版本不兼容

**现象**

```
ERR_PNPM_... <包名> requires dsh >= x.y.z
# 或
refusing to install <包名>: incompatible with DSH <版本>
```

**原因**：插件在 `engines.dsh` 或 peerDependencies 中限定了 DSH 版本范围。

**处理**（任选）

```bash
# A. 升级 DSH 到插件要求的版本
npm install -g @deepseek-ai/dsh@latest

# B. 升级该插件
dsh plugin --profile web add <包名>@latest

# C. 明确接受风险，跳过版本校验（谨慎）
dsh plugin --profile web allow-version <包名>@<版本> \
  --dsh-version <你的DSH版本> --accept-risk
```

选项 C 只应在确认插件可用时使用；版本不匹配可能导致启动崩溃。

---

## 6. desktop profile 被桌面版占用

**现象**

```
error: profile "desktop" is managed exclusively by the Electron application
# 或
Open DeepSeek Harness Desktop once to initialize its profile, then fully quit it before running dsh plugin --profile desktop.
```

**原因**：`desktop` 是桌面版保留 profile，只能由桌面版自带的命令管理。

**处理**

1. 先启动一次 Linux 桌面版 DSH，让它初始化 `~/.dsh/profiles/desktop`；
2. **完全退出**桌面版（不是最小化到托盘）；
3. 使用桌面版自带的 `dsh` 命令执行安装；
4. 若终端里没有该命令，改用 `--no-install` 写配置，再在桌面版「设置 → 插件」里手动安装。

---

## 7. 校验失败：`dsh --dump-config` 报错

**现象**：`install.sh` 最后一步提示「配置校验失败」。

**处理**

```bash
dsh --profile web --dump-config
# 查看具体报错，常见原因：
#  - 某个 bundle 未安装成功（node_modules 缺包）
#  - cordis.patch.yml 里 patch 了不存在的 id
#  - YAML 缩进错误
```

逐个排查：

```bash
ls ~/.dsh/profiles/web/node_modules | head
dsh plugin --profile web install
```

确认无误后重试；配置坏了就用 `bash rollback.sh --profile web` 回滚。

---

## 8. 启动后登录不了 / 一直要求登录

DeepSeek 账号使用设备码登录，凭据保存在 `~/.dsh/.credentials.yaml`，**不随本仓库迁移**。

```bash
dsh web
# 按界面提示在浏览器里确认设备码
```

如果反复要求登录：

- 确认系统时间准确（设备码有有效期）；
- 检查 `~/.dsh/.credentials.yaml` 是否可写；
- 删除该文件后重新登录（会丢失旧凭据）。

---

## 9. GPT 中转模型报 401 / 找不到 key

**原因**：`llm-pi-ai` 的 `gpt` provider 通过环境变量 `GPT_API_KEY` 取密钥，进程启动时读取。

**处理**

```bash
export GPT_API_KEY=sk-你的key
dsh web
```

持久化写入 `~/.bashrc` 或 `~/.profile` 后**重新登录/重启终端**再启动 DSH。

桌面版（从应用菜单启动）不会继承终端环境变量，需在 `~/.profile` / `~/.config/environment.d/` 中设置后重新登录桌面会话。

---

## 10. 端口被占用 / 打不开 Web UI

```bash
dsh web --help        # 查看该版本支持的应用参数
ss -lntp | grep node  # 查看已占用端口
```

若版本没有端口开关，可在 profile 的 `cordis.patch.yml` 里给 web 相关条目改监听端口，
或先杀掉占用进程再启动。

---

## 11. 局域网/公网暴露风险

`cordis.patch.yml` 中 `remote-web-ui` 配置为：

```yaml
lanBind: true
autoTunnel: true
```

- `lanBind: true`：监听所有网卡，同一局域网内可访问；
- `autoTunnel: true`：启动时自动建立 cloudflared 公网隧道。

不需要时改成：

```yaml
- id: remote-web-ui
  name: "@linxin666/dsh-remote-web-ui"
  config:
    lanBind: false
    autoTunnel: false
```

然后重启 DSH。隧道依赖 `cloudflared` 二进制，下载失败多半是网络问题，可配置代理或改用内网访问。

---

## 12. 迁移后设置没生效

检查三件事：

1. **profile 对不对**：`install.sh` 默认写 `web`；桌面版是 `desktop`。启动参数必须一致（`dsh web` ↔ `web`）。
2. **文件在不在**：`ls ~/.dsh/profiles/<profile>/` 应能看到 `cordis.patch.yml` 与 `package.json`。
3. **插件装没装**：`ls ~/.dsh/profiles/<profile>/node_modules` 应有 12 个包。

确认后重启 DSH；仍不生效可运行 `dsh --profile <profile> --dump-config` 查看组合后的实际配置。

---

## 13. 想彻底重来

```bash
# 备份整个 profile 后重建
mv ~/.dsh/profiles/web ~/.dsh/profiles/web.bak
cd dsh-linux-profile && bash install.sh --profile web
```

`dsh` 会在首次启动时用内置模板重新初始化 profile。
