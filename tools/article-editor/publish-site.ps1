Add-Type -AssemblyName System.Windows.Forms

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$hugo = "C:\Users\ky\AppData\Local\Microsoft\WinGet\Packages\Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe\hugo.exe"

function Find-Git {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($known in @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Users\ky\AppData\Local\Programs\Git\cmd\git.exe",
        "C:\Users\ky\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe"
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
    if (-not (Test-Path -LiteralPath $hugo -PathType Leaf)) { throw "找不到 Hugo，無法進行發布前檢查。" }
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
        & $hugo --minify
        if ($LASTEXITCODE -ne 0) { throw "Hugo 建置失敗，尚未發布。" }

        $changes = (& $git status --short) -join "`r`n"
        if ([string]::IsNullOrWhiteSpace($changes)) {
            Show-Message "目前沒有需要發布的新變更。`r`n`r`nGitHub 與 Cloudflare 不會重新建置。"
            return
        }

        & $git add --all
        if ($LASTEXITCODE -ne 0) { throw "無法整理待發布檔案。" }

        & $git commit -m ("更新網站 " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
        if ($LASTEXITCODE -ne 0) { throw "無法建立 Git 版本。" }

        & $git push origin main
        if ($LASTEXITCODE -ne 0) { throw "GitHub 上傳失敗；本機內容仍安全保留。" }

        Show-Message "網站資料已成功上傳 GitHub。`r`n`r`nCloudflare Pages 已自動開始建置公開網站，通常幾分鐘後完成。"
    } finally { Pop-Location }
} catch {
    Show-Message ("發布失敗：`r`n" + $_.Exception.Message) "Error"
    exit 1
}
