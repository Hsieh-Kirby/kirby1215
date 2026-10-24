Add-Type -AssemblyName System.Windows.Forms

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Find-Hugo {
    $command = Get-Command hugo.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($known in @(
        "C:\Program Files\Hugo\bin\hugo.exe",
        "C:\Program Files\Hugo\hugo.exe"
    )) {
        if (Test-Path -LiteralPath $known -PathType Leaf) { return $known }
    }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $wingetRoot -PathType Container) {
        $wingetHugo = Get-ChildItem -LiteralPath $wingetRoot -Filter hugo.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*Hugo.Hugo.Extended*" } |
            Select-Object -First 1
        if ($wingetHugo) { return $wingetHugo.FullName }
    }
    return $null
}

function Find-Git {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($known in @(
        "C:\Program Files\Git\cmd\git.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe"),
        (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe")
    )) {
        if (Test-Path -LiteralPath $known -PathType Leaf) { return $known }
    }
    return $null
}

function Ensure-GitIdentity([string]$GitPath) {
    $name = (& $GitPath config --local user.name 2>$null)
    $email = (& $GitPath config --local user.email 2>$null)
    if ([string]::IsNullOrWhiteSpace(($name -join ''))) {
        & $GitPath config --local user.name "Kuang-Yu Hsieh"
        if ($LASTEXITCODE -ne 0) { throw "無法設定 Git 作者姓名。" }
    }
    if ([string]::IsNullOrWhiteSpace(($email -join ''))) {
        & $GitPath config --local user.email "Hsieh-Kirby@users.noreply.github.com"
        if ($LASTEXITCODE -ne 0) { throw "無法設定 Git 作者信箱。" }
    }
}

function Show-Message([string]$Text, [string]$Icon = "Information") {
    [Windows.Forms.MessageBox]::Show($Text, "Kirby1215 發布網站", "OK", $Icon) | Out-Null
}

try {
    $hugo = Find-Hugo
    if (-not $hugo) { throw "找不到 Hugo Extended，無法進行發布前檢查。請先安裝 Hugo Extended。" }
    if (-not (Test-Path -LiteralPath (Join-Path $SiteRoot ".git"))) { throw "網站尚未連接 GitHub。" }
    $git = Find-Git
    if (-not $git) { throw "找不到 Git，無法發布到 GitHub。" }

    $answer = [Windows.Forms.MessageBox]::Show(
        "即將檢查網站並發布到 GitHub。`r`n`r`n如果已完成 Cloudflare Pages 同步設定，這次上傳也會自動更新 Cloudflare。要繼續嗎？",
        "確認發布",
        "YesNo",
        "Question"
    )
    if ($answer -ne "Yes") { return }

    Push-Location $SiteRoot
    try {
        Ensure-GitIdentity $git

        # Check GitHub before creating another local commit. Without this check,
        # a change published from another computer makes the later push fail as
        # non-fast-forward and leaves the two copies on different histories.
        & $git fetch origin main
        if ($LASTEXITCODE -ne 0) { throw "無法連線到 GitHub。請檢查網路或 GitHub 登入狀態。" }

        $counts = ((& $git rev-list --left-right --count HEAD...origin/main) -join " ").Trim() -split '\s+'
        if ($LASTEXITCODE -ne 0 -or $counts.Count -lt 2) { throw "無法比較本機與 GitHub 的版本。" }
        $ahead = [int]$counts[0]
        $behind = [int]$counts[1]

        if ($behind -gt 0) {
            if ($ahead -gt 0) {
                Show-Message "本機與 GitHub 各有尚未合併的版本，為避免覆蓋文章，已停止發布。`r`n`r`n請先處理版本衝突，不要使用強制上傳。" "Warning"
            } else {
                Show-Message "GitHub 上有 $behind 個較新版本。`r`n`r`n請先回到網站管理介面按「同步 GitHub 最新資料」，再重新發布。" "Warning"
            }
            return
        }

        & $hugo --minify
        if ($LASTEXITCODE -ne 0) { throw "Hugo 建置失敗，尚未發布。" }

        $changes = (& $git status --short) -join "`r`n"
        if ([string]::IsNullOrWhiteSpace($changes)) {
            if ($ahead -eq 0) {
                Show-Message "目前沒有需要發布的新變更。`r`n`r`nGitHub 與 Cloudflare 不會重新建置。"
                return
            }
        } else {
            & $git add --all
            if ($LASTEXITCODE -ne 0) { throw "無法整理待發布檔案。" }

            & $git commit -m ("更新網站 " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
            if ($LASTEXITCODE -ne 0) { throw "無法建立 Git 版本。" }
        }

        & $git push origin main
        if ($LASTEXITCODE -ne 0) { throw "GitHub 上傳失敗；本機內容仍安全保留。" }

        Show-Message "網站資料已成功上傳 GitHub。`r`n`r`nCloudflare Pages 應會自動開始建置；這個畫面只代表 GitHub 上傳成功，不代表 Cloudflare 已部署完成。請稍候幾分鐘後開啟網站確認新文章。"
    } finally { Pop-Location }
} catch {
    Show-Message ("發布失敗：`r`n" + $_.Exception.Message) "Error"
    exit 1
}
