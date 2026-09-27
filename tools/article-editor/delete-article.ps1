Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PostsRoot = Join-Path $SiteRoot "content\posts"
$StaticRoot = Join-Path $SiteRoot "static"

function Show-Info([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 刪除文章", "OK", "Information") | Out-Null
}

function Show-ErrorMessage([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 刪除文章", "OK", "Error") | Out-Null
}

function Get-PostInfo([System.IO.FileInfo]$File) {
    $text = [System.IO.File]::ReadAllText($File.FullName)
    $titleMatch = [regex]::Match($text, '(?m)^title:\s*["'']?(.*?)["'']?\s*$')
    $dateMatch = [regex]::Match($text, '(?m)^date:\s*["'']?([^"''\r\n]+)')
    $title = if ($titleMatch.Success) { $titleMatch.Groups[1].Value.Trim() } else { $File.BaseName }
    $date = if ($dateMatch.Success) { $dateMatch.Groups[1].Value.Trim() } else { "日期不明" }
    return [pscustomobject]@{
        Display = "$date　$title"
        Title = $title
        Date = $date
        Path = $File.FullName
        Content = $text
    }
}

function Get-LocalImageReferences([string]$Content) {
    $references = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Content, '!\[[^\]]*\]\(([^)]+)\)')) {
        $references.Add($match.Groups[1].Value.Trim('<', '>'))
    }
    foreach ($match in [regex]::Matches($Content, '(?m)^cover:\s*["'']?([^"''\r\n]+)')) {
        $references.Add($match.Groups[1].Value.Trim())
    }
    foreach ($match in [regex]::Matches($Content, '<img[^>]+src=["'']([^"'']+)["'']', 'IgnoreCase')) {
        $references.Add($match.Groups[1].Value.Trim())
    }
    return @($references | Select-Object -Unique)
}

function Convert-UrlToStaticPath([string]$Url) {
    $clean = $Url.Split('?')[0].Split('#')[0]
    if ($clean -match '^https?://') { return $null }
    $clean = [System.Uri]::UnescapeDataString($clean)
    $clean = $clean -replace '^/kirby1215/', ''
    $clean = $clean -replace '^/', ''
    if (-not $clean.StartsWith('images/')) { return $null }

    $relative = $clean.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $StaticRoot $relative))
    $staticFull = [System.IO.Path]::GetFullPath($StaticRoot) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($staticFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $candidate
}

function Load-Posts {
    $postList.Items.Clear()
    Get-ChildItem -LiteralPath $PostsRoot -Filter '*.md' -File |
        ForEach-Object { Get-PostInfo $_ } |
        Sort-Object Date -Descending |
        ForEach-Object { [void]$postList.Items.Add($_) }
    $statusLabel.Text = "共有 $($postList.Items.Count) 篇文章"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Kirby1215 刪除文章"
$form.Size = New-Object System.Drawing.Size(850, 680)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10)
$form.MinimumSize = New-Object System.Drawing.Size(760, 600)

$instruction = New-Object System.Windows.Forms.Label
$instruction.Text = "選擇要刪除的文章。文章與專用圖片會移到備份區，可日後復原。"
$instruction.Location = New-Object System.Drawing.Point(20, 18)
$instruction.Size = New-Object System.Drawing.Size(790, 25)
$form.Controls.Add($instruction)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(20, 50)
$searchBox.Size = New-Object System.Drawing.Size(620, 28)
$form.Controls.Add($searchBox)

$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Text = "搜尋"
$searchButton.Location = New-Object System.Drawing.Point(655, 47)
$searchButton.Size = New-Object System.Drawing.Size(80, 34)
$form.Controls.Add($searchButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "全部"
$clearButton.Location = New-Object System.Drawing.Point(745, 47)
$clearButton.Size = New-Object System.Drawing.Size(70, 34)
$form.Controls.Add($clearButton)

$postList = New-Object System.Windows.Forms.ListBox
$postList.Location = New-Object System.Drawing.Point(20, 92)
$postList.Size = New-Object System.Drawing.Size(795, 360)
$postList.Anchor = "Top,Bottom,Left,Right"
$postList.DisplayMember = "Display"
$form.Controls.Add($postList)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 465)
$statusLabel.Size = New-Object System.Drawing.Size(795, 25)
$statusLabel.Anchor = "Bottom,Left,Right"
$form.Controls.Add($statusLabel)

$detailsBox = New-Object System.Windows.Forms.TextBox
$detailsBox.Location = New-Object System.Drawing.Point(20, 495)
$detailsBox.Size = New-Object System.Drawing.Size(795, 65)
$detailsBox.Anchor = "Bottom,Left,Right"
$detailsBox.Multiline = $true
$detailsBox.ReadOnly = $true
$form.Controls.Add($detailsBox)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = "備份並刪除"
$deleteButton.Location = New-Object System.Drawing.Point(20, 580)
$deleteButton.Size = New-Object System.Drawing.Size(140, 38)
$deleteButton.Anchor = "Bottom,Left"
$form.Controls.Add($deleteButton)

$openBackupButton = New-Object System.Windows.Forms.Button
$openBackupButton.Text = "開啟刪除備份"
$openBackupButton.Location = New-Object System.Drawing.Point(175, 580)
$openBackupButton.Size = New-Object System.Drawing.Size(150, 38)
$openBackupButton.Anchor = "Bottom,Left"
$form.Controls.Add($openBackupButton)

$postList.Add_SelectedIndexChanged({
    if ($postList.SelectedItem) {
        $selected = $postList.SelectedItem
        $images = Get-LocalImageReferences $selected.Content
        $detailsBox.Text = "檔案：$($selected.Path)`r`n找到 $($images.Count) 個本機圖片引用。"
    }
})

$searchButton.Add_Click({
    $keyword = $searchBox.Text.Trim()
    if (-not $keyword) { Load-Posts; return }
    $postList.Items.Clear()
    Get-ChildItem -LiteralPath $PostsRoot -Filter '*.md' -File |
        ForEach-Object { Get-PostInfo $_ } |
        Where-Object { $_.Title -like "*$keyword*" -or $_.Content -like "*$keyword*" } |
        Sort-Object Date -Descending |
        ForEach-Object { [void]$postList.Items.Add($_) }
    $statusLabel.Text = "搜尋到 $($postList.Items.Count) 篇文章"
})

$clearButton.Add_Click({
    $searchBox.Clear()
    Load-Posts
})

$deleteButton.Add_Click({
    if (-not $postList.SelectedItem) {
        Show-ErrorMessage "請先選擇一篇文章。"
        return
    }

    $selected = $postList.SelectedItem
    $imageUrls = Get-LocalImageReferences $selected.Content
    $allOtherContent = Get-ChildItem -LiteralPath $PostsRoot -Filter '*.md' -File |
        Where-Object { $_.FullName -ne $selected.Path } |
        ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
    $sharedText = $allOtherContent -join "`n"

    $filesToMove = New-Object System.Collections.Generic.List[string]
    $sharedImages = New-Object System.Collections.Generic.List[string]
    foreach ($url in $imageUrls) {
        $imagePath = Convert-UrlToStaticPath $url
        if (-not $imagePath -or -not (Test-Path -LiteralPath $imagePath)) { continue }
        if ($sharedText.Contains($url)) { $sharedImages.Add($imagePath) }
        elseif (-not $filesToMove.Contains($imagePath)) { $filesToMove.Add($imagePath) }
    }

    $message = "即將移至備份區：`r`n`r`n文章：$($selected.Title)`r`n圖片：$($filesToMove.Count) 個"
    if ($sharedImages.Count -gt 0) {
        $message += "`r`n共享圖片：$($sharedImages.Count) 個（為避免其他文章缺圖，將保留）"
    }
    $message += "`r`n`r`n確定要繼續嗎？"
    $answer = [System.Windows.Forms.MessageBox]::Show($message, "確認刪除", "YesNo", "Warning")
    if ($answer -ne "Yes") { return }

    try {
        $backupRoot = Join-Path $SiteRoot ("migration-backups\deleted-posts\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        $postBackup = Join-Path $backupRoot "content\posts"
        New-Item -ItemType Directory -Path $postBackup -Force | Out-Null

        foreach ($imagePath in $filesToMove) {
            $relative = $imagePath.Substring($StaticRoot.Length).TrimStart('\')
            $destination = Join-Path (Join-Path $backupRoot "static") $relative
            $destinationFolder = Split-Path -Parent $destination
            New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
            Move-Item -LiteralPath $imagePath -Destination $destination
        }

        Move-Item -LiteralPath $selected.Path -Destination (Join-Path $postBackup ([System.IO.Path]::GetFileName($selected.Path)))
        Show-Info "文章已從網站移除並完成備份。`r`n`r`n備份位置：`r`n$backupRoot`r`n`r`n下次發布到 GitHub 時，線上文章才會同步刪除。"
        Load-Posts
        $detailsBox.Clear()
    } catch {
        Show-ErrorMessage "刪除失敗：`r`n$($_.Exception.Message)"
    }
})

$openBackupButton.Add_Click({
    $folder = Join-Path $SiteRoot "migration-backups\deleted-posts"
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    Start-Process explorer.exe $folder
})

Load-Posts
[void]$form.ShowDialog()
