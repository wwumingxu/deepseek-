# 给 Linux 上的 DSH Agent：安装任务说明书

> 这份文件是给「在 Linux 上执行安装的 DSH Agent」看的，人类用户只需把仓库地址交给它。
> 目标：把本仓库的 DSH profile 配置安装到本机，装好 12 个插件，并验证可启动。

## 0. 硬约束（必须遵守）

- **不要**复制或上传任何密钥文件；本仓库不含 `.credentials.yaml`、API Key。
- **不要**删除用户已有的 profile 配置：`install.sh` 会自动备份到
  `$PROFILE_DIR/.migration-backup-<时间戳>/`，保留备份。
- **不要**安装 `dsh-computer-use-win`：它声明 `os: ["win32"]`，在 Linux 上必定失败。
- 若目标 profile 是 `desktop`（Linux 桌面版），DSH 可能禁止命令行管理它；
  遇到该错误就改用 `--no-install` 写配置，再在界面里安装插件。
- 任何一步失败，先执行对应 `rollback.sh`，再报告错误原文，不要反复重试同一命令。

## 1. 环境检查

```bash
node -v      # 必须 >= 24.9.0，否则 DSH 无法运行
pnpm -v      # 缺失则 npm install -g pnpm
dsh --version
```

缺 Node ≥ 24.9 时先升级 Node（nvm 或 NodeSource），**不要**用低版本硬试。

## 2. 克隆

```bash
git clone https://github.com/wwumingxu/deepseek-.git dsh-linux-profile
cd dsh-linux-profile
```

仓库为私有：若 clone 提示认证失败，让用户提供 PAT，或先把仓库改为 Public。

## 3. 安装

```bash
bash install.sh --dry-run          # 先看它要做什么，不写任何文件
bash install.sh                    # 正式安装到 profile "web"
```

桌面版用户：

```bash
bash install.sh --profile desktop
```

## 4. 验证（三条都要通过）

```bash
dsh --profile web --dump-config > /tmp/dsh-ok.yml   # 退出码 0，且无报错
grep -c 'id:' /tmp/dsh-ok.yml                        # 配置层已合并
dsh web                                              # 能启动，浏览器可打开
```

`dsh web` 会前台占用终端；确认能访问后 `Ctrl+C` 即可，不算失败。

## 5. 装完必须告诉用户的三件事

1. 重新登录 DeepSeek 账号（凭据不随仓库迁移）。
2. 需要 GPT 中转模型时，设置环境变量 `GPT_API_KEY=<用户的 key>` 再启动。
3. `remote-web-ui` 默认 `lanBind: true` + `autoTunnel: true`，会把服务暴露到局域网/隧道；
   不需要时在设置里关掉。

## 6. 失败时的回滚

```bash
bash rollback.sh --list            # 列出备份
bash rollback.sh                   # 还原最近一次备份
```

回滚后再把报错原文（含命令与退出码）反馈给用户，不要自行猜测修改配置。
