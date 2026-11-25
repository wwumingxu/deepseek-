<#
.SYNOPSIS
    从当前 Windows 上的 DSH profile 重新导出迁移配置到本仓库的 profile/ 目录。

.DESCRIPTION
    读取 $env:DSH_PROFILE_DIR（或 -ProfileDir 指定）下的：
        package.json / cordis.patch.yml / cordis.yml / pnpm-workspace.yaml
    自动剔除仅支持 Windows 的插件，改写 profile 名称，写入 UTF-8 (无 BOM) + LF 换行。
    不会复制 node_modules、pnpm-lock.yaml、.credentials.yaml 或任何密钥。

.PARAMETER ProfileDir
    DSH profile 目录，默认 $env:DSH_PROFILE_DIR，再退回 ~/.dsh/profiles/desktop。

.PARAMETER OutDir
    输出目录，默认为本脚本上一级目录下的 profile/。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\export-from-windows.ps1

.EXAMPLE
    .\scripts\export-from-windows.ps1 -ProfileDir C:\Users\me\.dsh\profiles\desktop -OutDir .\profile
#>
[CmdletBinding()]
param(
    [string]$ProfileDir = $(if ($env:DSH_PROFILE_DIR) { $env:DSH_PROFILE_DIR } else { Join-Path $HOME '.dsh/profiles/desktop' }),
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile')
)

$ErrorActionPreference = 'Stop'

# 仅支持 win32、Linux 上无法安装的插件
$WinOnlyPackages = @('dsh-computer-use-win')

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $enc)
}

function ConvertTo-PrettyJson {
    param(
        [string]$Json,
        [int]$IndentSize = 2
    )
    $sb = New-Object System.Text.StringBuilder
    $depth = 0
    $inString = $false
    $escaped = $false
    $needNewline = $false

    for ($i = 0; $i -lt $Json.Length; $i++) {
        $c = $Json[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            continue
        }

        if ($c -eq '"') {
            if ($needNewline) {
                [void]$sb.Append("`n"); [void]$sb.Append(' ' * ($depth * $IndentSize)); $needNewline = $false
            }
            $inString = $true
            [void]$sb.Append($c)
        }
        elseif ($c -eq '{' -or $c -eq '[') {
            [void]$sb.Append($c)
            $depth++
            $needNewline = $true
        }
        elseif ($c -eq '}' -or $c -eq ']') {
            $depth--
            $opener = if ($c -eq '}') { '{' } else { '[' }
            if ($sb.Length -gt 0 -and $sb[$sb.Length - 1] -eq $opener) {
                [void]$sb.Append($c)
            }
            else {
                [void]$sb.Append("`n"); [void]$sb.Append(' ' * ($depth * $IndentSize))
                [void]$sb.Append($c)
            }
            $needNewline = $false
        }
        elseif ($c -eq ',') {
            [void]$sb.Append($c)
            $needNewline = $true
        }
        elseif ($c -eq ':') {
            [void]$sb.Append(': ')
            $needNewline = $false
        }
        elseif ([char]::IsWhiteSpace($c)) {
            continue
        }
        else {
            if ($needNewline) {
                [void]$sb.Append("`n"); [void]$sb.Append(' ' * ($depth * $IndentSize)); $needNewline = $false
            }
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString().TrimEnd("`r", "`n")
}

Write-Host "源 profile : $ProfileDir"
Write-Host "输出目录   : $OutDir"

$pkgPath = Join-Path $ProfileDir 'package.json'
if (-not (Test-Path $pkgPath)) {
    throw "找不到 $pkgPath。请确认 DSH 已初始化该 profile，或用 -ProfileDir 指定正确路径。"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------- package.json ----------
$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json

$removedDeps = @()
foreach ($name in $WinOnlyPackages) {
    if ($pkg.dependencies.PSObject.Properties.Name -contains $name) {
        $pkg.dependencies.PSObject.Properties.Remove($name)
        $removedDeps += $name
    }
}

$bundles = @($pkg.dsh.profile.bundles)
$keptBundles = @($bundles | Where-Object { $WinOnlyPackages -notcontains $_ })
$removedBundles = @($bundles | Where-Object { $WinOnlyPackages -contains $_ })

$pkg.name = 'dsh-profile-linux'
$pkg.dsh.profile.bundles = $keptBundles

$pkgJson = $pkg | ConvertTo-Json -Depth 32 -Compress
$pkgJson = ConvertTo-PrettyJson -Json $pkgJson -IndentSize 2
Write-Utf8NoBom -Path (Join-Path $OutDir 'package.json') -Text $pkgJson

Write-Host ""
Write-Host "插件依赖   : $(@($pkg.dependencies.PSObject.Properties).Count) 个"
Write-Host "bundle 顺序: $($keptBundles.Count) 项"
if ($removedDeps.Count -gt 0) {
    Write-Host "已剔除依赖 : $($removedDeps -join ', ')" -ForegroundColor Yellow
}
if ($removedBundles.Count -gt 0) {
    Write-Host "已剔除 bundle: $($removedBundles -join ', ')" -ForegroundColor Yellow
}

# ---------- 其余配置文件 ----------
foreach ($file in @('cordis.patch.yml', 'cordis.yml', 'pnpm-workspace.yaml')) {
    $src = Join-Path $ProfileDir $file
    if (-not (Test-Path $src)) {
        Write-Warning "跳过缺失文件: $file"
        continue
    }
    $text = Get-Content $src -Raw

    if ($file -eq 'cordis.patch.yml') {
        # 版本号按字符串写出，避免不同 YAML 解析器把它当数字
        $text = $text -replace '(?m)^(\s*welcomeNoticeVersion:\s*)([0-9][^\s"#]*)\s*$', '$1"$2"'
        if ($text -match 'sk-[A-Za-z0-9]') {
            throw "cordis.patch.yml 中疑似包含 API Key（sk-...），已中止。请先移除密钥，改用 apiKeyEnv 引用环境变量。"
        }
    }

    Write-Utf8NoBom -Path (Join-Path $OutDir $file) -Text $text
    Write-Host "已导出     : $file"
}

# ---------- 安全检查 ----------
$forbidden = @('.credentials.yaml', 'credentials.yml', '.env')
foreach ($bad in $forbidden) {
    if (Test-Path (Join-Path $OutDir $bad)) {
        throw "输出目录出现敏感文件 $bad，请删除后再提交。"
    }
}

Write-Host ""
Write-Host "导出完成。提交前请检查 git diff：" -ForegroundColor Green
Write-Host "  git add -A && git diff --cached"
Write-Host "  git commit -m 'sync from windows' && git push"
