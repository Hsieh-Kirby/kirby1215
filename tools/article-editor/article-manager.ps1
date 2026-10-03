Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ServerPidFile = Join-Path $PSScriptRoot ".hugo-server.pid"
$PreviewUrl = "http://localhost:1313/kirby1215/"

function Find-Hugo {
    $command = Get-Command hugo.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $known = "C:\Users\ky\AppData\Local\Microsoft\WinGet\Packages\Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe\hugo.exe"
    if (Test-Path -LiteralPath $known -PathType Leaf) { return $known }
    return $null
}

function Get-PreviewProcess {
    if (-not (Test-Path -LiteralPath $ServerPidFile -PathType Leaf)) { return $null }
    $savedPid = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $ServerPidFile -Raw).Trim(), [ref]$savedPid)) { return $null }
    return Get-Process -Id $savedPid -ErrorAction SilentlyContinue
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Kirby1215 網站管理"
$form.Size = New-Object System.Drawing.Size(610, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 11)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Kirby1215 網站管理"
$title.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 20)
$title.Location = New-Object System.Drawing.Point(38, 25)
$title.AutoSize = $true
$form.Controls.Add($title)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "新增、修改或刪除後，先在本機預覽，確認完成再發布。"
$hint.Location = New-Object System.Drawing.Point(41, 72)
$hint.Size = New-Object System.Drawing.Size(520, 28)
$form.Controls.Add($hint)

function Open-Tool([string]$ScriptName) {
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptPath + '"'))
}

function Add-ActionButton([string]$Text, [int]$X, [int]$Y, [int]$Width, [string]$ScriptName) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 52)
    $button.Add_Click({ Open-Tool $ScriptName }.GetNewClosure())
    $form.Controls.Add($button)
    return $button
}

[void](Add-ActionButton "新增文章" 42 112 245 "article-editor.ps1")
[void](Add-ActionButton "修改文章" 307 112 245 "edit-article.ps1")
[void](Add-ActionButton "刪除文章與專用圖片" 42 178 245 "delete-article.ps1")
[void](Add-ActionButton "批次修改分類與專題" 307 178 245 "bulk-category.ps1")

$previewGroup = New-Object System.Windows.Forms.GroupBox
$previewGroup.Text = "本機 Hugo 預覽"
$previewGroup.Location = New-Object System.Drawing.Point(42, 250)
$previewGroup.Size = New-Object System.Drawing.Size(510, 130)
$form.Controls.Add($previewGroup)

$previewStatus = New-Object System.Windows.Forms.Label
$previewStatus.Location = New-Object System.Drawing.Point(18, 28)
$previewStatus.Size = New-Object System.Drawing.Size(465, 26)
$previewGroup.Controls.Add($previewStatus)

$startPreviewButton = New-Object System.Windows.Forms.Button
$startPreviewButton.Text = "啟動並開啟預覽"
$startPreviewButton.Location = New-Object System.Drawing.Point(18, 65)
$startPreviewButton.Size = New-Object System.Drawing.Size(190, 42)
$previewGroup.Controls.Add($startPreviewButton)

$openPreviewButton = New-Object System.Windows.Forms.Button
$openPreviewButton.Text = "開啟預覽網頁"
$openPreviewButton.Location = New-Object System.Drawing.Point(218, 65)
$openPreviewButton.Size = New-Object System.Drawing.Size(145, 42)
$previewGroup.Controls.Add($openPreviewButton)

$stopPreviewButton = New-Object System.Windows.Forms.Button
$stopPreviewButton.Text = "停止伺服器"
$stopPreviewButton.Location = New-Object System.Drawing.Point(373, 65)
$stopPreviewButton.Size = New-Object System.Drawing.Size(120, 42)
$previewGroup.Controls.Add($stopPreviewButton)

function Update-PreviewStatus {
    $process = Get-PreviewProcess
    if ($process) {
        $previewStatus.Text = "狀態：伺服器運作中（關閉管理介面後仍會繼續）"
        $previewStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $previewStatus.Text = "狀態：尚未啟動"
        $previewStatus.ForeColor = [System.Drawing.Color]::DimGray
        if (Test-Path -LiteralPath $ServerPidFile) { Remove-Item -LiteralPath $ServerPidFile -Force }
    }
}

$startPreviewButton.Add_Click({
    try {
        $process = Get-PreviewProcess
        if (-not $process) {
            $hugo = Find-Hugo
            if (-not $hugo) { throw "找不到 Hugo，無法啟動本機預覽。" }
            $process = Start-Process -FilePath $hugo -ArgumentList @('server','-D','--disableFastRender') -WorkingDirectory $SiteRoot -WindowStyle Hidden -PassThru
            [System.IO.File]::WriteAllText($ServerPidFile, [string]$process.Id)
            Start-Sleep -Milliseconds 1200
        }
        Update-PreviewStatus
        Start-Process $PreviewUrl
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "無法啟動預覽", "OK", "Error") | Out-Null
    }
})

$openPreviewButton.Add_Click({ Start-Process $PreviewUrl })

$stopPreviewButton.Add_Click({
    $process = Get-PreviewProcess
    if ($process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $ServerPidFile) { Remove-Item -LiteralPath $ServerPidFile -Force }
    Update-PreviewStatus
})

$publishButton = New-Object System.Windows.Forms.Button
$publishButton.Text = "上傳到 GitHub 並同步發布到 Cloudflare"
$publishButton.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 12, [System.Drawing.FontStyle]::Bold)
$publishButton.Location = New-Object System.Drawing.Point(42, 402)
$publishButton.Size = New-Object System.Drawing.Size(510, 58)
$publishButton.Add_Click({ Open-Tool "publish-site.ps1" })
$form.Controls.Add($publishButton)

$publishHint = New-Object System.Windows.Forms.Label
$publishHint.Text = "GitHub 僅保存網站資料；公開網站由 Cloudflare Pages 提供。"
$publishHint.Location = New-Object System.Drawing.Point(44, 470)
$publishHint.Size = New-Object System.Drawing.Size(505, 28)
$publishHint.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($publishHint)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "退出"
$exitButton.Location = New-Object System.Drawing.Point(422, 525)
$exitButton.Size = New-Object System.Drawing.Size(130, 42)
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

Update-PreviewStatus
[void]$form.ShowDialog()
