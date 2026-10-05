Add-Type -AssemblyName System.Windows.Forms

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

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

function Show-Message([string]$Text, [string]$Icon = "Information") {
    [Windows.Forms.MessageBox]::Show($Text, "Kirby1215 同步最新資料", "OK", $Icon) | Out-Null
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $SiteRoot ".git"))) {
        throw "這個網站資料夾尚未連接 GitHub。第一次使用新電腦時，請先從 GitHub 複製完整專案。"
    }

    $git = Find-Git
    if (-not $git) { throw "找不到 Git。請先安裝 Git for Windows，再重新開啟網站管理工具。" }

    Push-Location $SiteRoot
    try {
        $localChanges = (& $git status --porcelain) -join "`r`n"
        if ($LASTEXITCODE -ne 0) { throw "無法檢查本機網站資料。" }
        if (-not [string]::IsNullOrWhiteSpace($localChanges)) {
            Show-Message "本機還有尚未發布的修改，因此沒有進行同步。`r`n`r`n請先按「上傳到 GitHub 並同步發布到 Cloudflare」，或確認這些修改不再需要後再處理。這項保護可避免文章被覆蓋。" "Warning"
            return
        }

        & $git fetch origin main
        if ($LASTEXITCODE -ne 0) { throw "無法連線到 GitHub。請檢查網路或 GitHub 登入狀態。" }

        $counts = ((& $git rev-list --left-right --count HEAD...origin/main) -join " ").Trim() -split '\s+'
        if ($LASTEXITCODE -ne 0 -or $counts.Count -lt 2) { throw "無法比較本機與 GitHub 的版本。" }
        $ahead = [int]$counts[0]
        $behind = [int]$counts[1]

        if ($ahead -gt 0) {
            Show-Message "本機有 $ahead 個尚未上傳的版本，因此沒有下載 GitHub 資料。`r`n`r`n請先使用發布功能上傳，避免兩台電腦的內容互相覆蓋。" "Warning"
            return
        }
        if ($behind -eq 0) {
            Show-Message "本機已經是 GitHub 的最新版本，不需要下載。"
            return
        }

        $before = (& $git rev-parse HEAD).Trim()
        & $git merge --ff-only origin/main
        if ($LASTEXITCODE -ne 0) { throw "同步無法安全完成；本機檔案沒有被強制覆蓋。" }

        $changedFiles = @(& $git diff --name-only $before HEAD | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Show-Message "同步完成。`r`n`r`n已從 GitHub 下載 $behind 個新版本，共更新 $($changedFiles.Count) 個檔案。`r`n現在可以開始新增或編輯文章。"
    } finally {
        Pop-Location
    }
} catch {
    Show-Message ("同步失敗：`r`n" + $_.Exception.Message) "Error"
    exit 1
}
