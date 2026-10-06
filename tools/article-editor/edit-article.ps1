Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PostsRoot = Join-Path $SiteRoot "content\posts"
$ContentRoots = @(
    $PostsRoot,
    (Join-Path $SiteRoot "content\itsuwa"),
    (Join-Path $SiteRoot "content\japan")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$StaticRoot = Join-Path $SiteRoot "static"
$script:SelectedPost = $null
$script:NewImages = @()
$script:NewCover = $null

function Get-SeriesChoices {
    $names = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $ContentRoots -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_index.md' } | ForEach-Object {
        $raw = [System.IO.File]::ReadAllText($_.FullName)
        $match = [regex]::Match($raw, '(?ms)^series:\s*\r?\n((?:\s+-[^\r\n]*\r?\n?)*)')
        if ($match.Success) {
            [regex]::Matches($match.Groups[1].Value, '(?m)^\s+-\s*["'']?([^"''\r\n]+)') | ForEach-Object {
                $name = $_.Groups[1].Value.Trim()
                if ($name) { $names.Add($name) }
            }
        }
    }
    return @("無專題") + @($names | Sort-Object -Unique)
}

$SeriesChoices = Get-SeriesChoices

function Show-Info([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 編輯文章", "OK", "Information") | Out-Null
}

function Show-ErrorMessage([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 編輯文章", "OK", "Error") | Out-Null
}

function Format-ArticleParagraphs([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $normalized = $Text -replace "`r`n?", "`n"
    $blocks = [regex]::Split($normalized, "`n[ `t]*`n")
    $formatted = foreach ($block in $blocks) {
        $lines = @($block -split "`n")
        $isMarkdownBlock = $lines.Count -gt 1 -and ($lines | Where-Object {
            $_.Trim() -match '^(?:```|~~~|#{1,6}\s|>|[-*+]\s|\d+[.)]\s|\|)'
        }).Count -eq $lines.Count
        if ($lines.Count -gt 1 -and -not $isMarkdownBlock) {
            $lines -join "`r`n`r`n"
        } else {
            $lines -join "`r`n"
        }
    }
    return ($formatted -join "`r`n`r`n").Trim()
}

. (Join-Path $PSScriptRoot "image-tools.ps1")

function Split-Post([string]$Text) {
    $match = [regex]::Match($Text, '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
    if (-not $match.Success) { throw "文章缺少正確的 YAML 開頭資料。" }
    return [pscustomobject]@{ FrontMatter = $match.Groups[1].Value; Body = $match.Groups[2].Value }
}

function Get-Value([string]$FrontMatter, [string]$Name) {
    $pattern = '(?m)^{0}:\s*["'']?([^"''\r\n]+)' -f [regex]::Escape($Name)
    $match = [regex]::Match($FrontMatter, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ""
}

function Convert-WebImageToLocalPath([string]$WebPath) {
    if ([string]::IsNullOrWhiteSpace($WebPath) -or $WebPath -match '^https?://') { return $null }
    $clean = $WebPath.Trim('"', "'", '<', '>') -replace '[?#].*$', ''
    try { $clean = [Uri]::UnescapeDataString($clean) } catch { }
    $clean = $clean -replace '^/kirby1215/', '' -replace '^/', ''
    $candidate = Join-Path $StaticRoot ($clean -replace '/', '\')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return $null
}

function Show-ImagePreview([string]$ImagePath) {
    if ($previewPicture.Image) {
        $oldImage = $previewPicture.Image
        $previewPicture.Image = $null
        $oldImage.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        $previewMessage.Text = "找不到可預覽的圖片"
        return
    }
    try {
        $loaded = [System.Drawing.Image]::FromFile($ImagePath)
        try { $previewPicture.Image = New-Object System.Drawing.Bitmap($loaded) } finally { $loaded.Dispose() }
        $previewMessage.Text = [System.IO.Path]::GetFileName($ImagePath)
    } catch {
        $previewMessage.Text = "此格式儲存後可在網頁預覽"
    }
}

function Refresh-ImagePreviewList([string]$FrontMatter, [string]$Body) {
    $imagePreviewList.Items.Clear()
    $seen = @{}
    $cover = Get-Value $FrontMatter "cover"
    if ($cover) {
        $local = Convert-WebImageToLocalPath $cover
        if ($local) {
            [void]$imagePreviewList.Items.Add([pscustomobject]@{ Display = "封面：$([System.IO.Path]::GetFileName($local))"; Path = $local })
            $seen[$local.ToLowerInvariant()] = $true
        }
    }
    foreach ($match in [regex]::Matches($Body, '!\[[^\]]*\]\((?:<([^>]+)>|([^\)]+))\)')) {
        $imageReference = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value.Trim() }
        $local = Convert-WebImageToLocalPath $imageReference
        if ($local -and -not $seen.ContainsKey($local.ToLowerInvariant())) {
            [void]$imagePreviewList.Items.Add([pscustomobject]@{ Display = "內文：$([System.IO.Path]::GetFileName($local))"; Path = $local })
            $seen[$local.ToLowerInvariant()] = $true
        }
    }
    for ($i = 0; $i -lt $script:NewImages.Count; $i++) {
        $path = [string]$script:NewImages[$i]
        [void]$imagePreviewList.Items.Add([pscustomobject]@{ Display = "新圖片 $($i + 1)：$([System.IO.Path]::GetFileName($path))"; Path = $path })
    }
    if ($script:NewCover) {
        [void]$imagePreviewList.Items.Insert(0, [pscustomobject]@{ Display = "新封面：$([System.IO.Path]::GetFileName($script:NewCover))"; Path = [string]$script:NewCover })
    }
    if ($imagePreviewList.Items.Count -gt 0) { $imagePreviewList.SelectedIndex = 0 }
    else { Show-ImagePreview $null }
}

function Set-Value([string]$FrontMatter, [string]$Name, [string]$Value) {
    $safe = $Value.Replace("\", "\\").Replace('"', '\"')
    $line = "$Name`: `"$safe`""
    $pattern = "(?m)^$([regex]::Escape($Name)):.*$"
    if ([regex]::IsMatch($FrontMatter, $pattern)) { return [regex]::Replace($FrontMatter, $pattern, $line, 1) }
    return $FrontMatter.TrimEnd() + "`r`n" + $line
}

function Set-Category([string]$FrontMatter, [string]$Category) {
    $block = "categories:`r`n  - `"$Category`""
    $pattern = '(?ms)^categories:\s*\r?\n(?:\s+-[^\r\n]*\r?\n?)*'
    if ([regex]::IsMatch($FrontMatter, $pattern)) { return [regex]::Replace($FrontMatter, $pattern, $block + "`r`n", 1) }
    return $FrontMatter.TrimEnd() + "`r`n" + $block
}

function Get-Series([string]$FrontMatter) {
    $match = [regex]::Match($FrontMatter, '(?ms)^series:\s*\r?\n((?:\s+-[^\r\n]*\r?\n?)*)')
    if (-not $match.Success) { return "無專題" }
    $items = @([regex]::Matches($match.Groups[1].Value, '(?m)^\s+-\s*["'']?([^"''\r\n]+)') |
        ForEach-Object { $_.Groups[1].Value.Trim() })
    if ($items.Count -eq 0) { return "無專題" }
    return ($items -join '、')
}

function Set-Series([string]$FrontMatter, [string]$Series) {
    $pattern = '(?ms)^series:\s*\r?\n(?:\s+-[^\r\n]*\r?\n?)*'
    if ($Series -eq "無專題" -or [string]::IsNullOrWhiteSpace($Series)) {
        return [regex]::Replace($FrontMatter, $pattern, '', 1).TrimEnd()
    }
    $lines = @($Series -split '[、,，]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { '  - "' + $_.Trim() + '"' })
    $block = "series:`r`n" + ($lines -join "`r`n")
    if ([regex]::IsMatch($FrontMatter, $pattern)) {
        return [regex]::Replace($FrontMatter, $pattern, $block + "`r`n", 1)
    }
    return $FrontMatter.TrimEnd() + "`r`n" + $block
}

function Set-CoverAsFirstImage([string]$Body, [string]$OldCover, [string]$NewCover, [string]$Title) {
    $updatedBody = $Body
    if (-not [string]::IsNullOrWhiteSpace($OldCover)) {
        $oldPattern = '(?m)^[ \t]*!\[[^\]]*\]\(' + [regex]::Escape($OldCover) + '(?:\s+["''][^"'']*["''])?\)[ \t]*\r?\n?'
        $updatedBody = [regex]::Replace($updatedBody, $oldPattern, '', 1)
    }
    $safeTitle = $Title.Replace(']', '\]')
    $coverMarkdown = "![$safeTitle]($NewCover)"
    if ([string]::IsNullOrWhiteSpace($updatedBody)) { return $coverMarkdown }
    return $coverMarkdown + "`r`n`r`n" + $updatedBody.TrimStart()
}

function Get-PostItems([string]$Keyword) {
    Get-ChildItem -LiteralPath $ContentRoots -Filter '*.md' -File |
        Where-Object { $_.Name -ne '_index.md' } | ForEach-Object {
        $raw = [System.IO.File]::ReadAllText($_.FullName)
        try {
            $parts = Split-Post $raw
            $title = Get-Value $parts.FrontMatter "title"
            $date = Get-Value $parts.FrontMatter "date"
            if (-not $title) { $title = $_.BaseName }
            if (-not $Keyword -or $title -like "*$Keyword*" -or $parts.Body -like "*$Keyword*") {
                $section = Split-Path -Leaf $_.DirectoryName
                $sectionLabel = if (Get-Value $parts.FrontMatter 'chapterized_part') { '專題目錄' } elseif (Get-Value $parts.FrontMatter 'book_landing') { '專題總目錄' } else {
                    switch ($section) { 'itsuwa' { '逸話' } 'japan' { '日本專題' } default { '文章' } }
                }
                [pscustomobject]@{ Display = "[$sectionLabel] $date　$title"; Title = $title; Date = $date; Path = $_.FullName; Raw = $raw }
            }
        } catch { }
    } | Sort-Object Date -Descending
}

function Load-List([string]$Keyword) {
    $postList.Items.Clear()
    Get-PostItems $Keyword | ForEach-Object { [void]$postList.Items.Add($_) }
    $countLabel.Text = "共 $($postList.Items.Count) 篇"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Kirby1215 編輯文章"
$form.Size = New-Object System.Drawing.Size(1380, 820)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10)
$form.MinimumSize = New-Object System.Drawing.Size(1250, 720)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(18, 18)
$searchBox.Size = New-Object System.Drawing.Size(260, 28)
$form.Controls.Add($searchBox)

$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Text = "搜尋文章"
$searchButton.Location = New-Object System.Drawing.Point(290, 15)
$searchButton.Size = New-Object System.Drawing.Size(100, 34)
$form.Controls.Add($searchButton)

$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Location = New-Object System.Drawing.Point(18, 55)
$countLabel.Size = New-Object System.Drawing.Size(370, 24)
$form.Controls.Add($countLabel)

$postList = New-Object System.Windows.Forms.ListBox
$postList.Location = New-Object System.Drawing.Point(18, 82)
$postList.Size = New-Object System.Drawing.Size(372, 625)
$postList.Anchor = "Top,Bottom,Left"
$postList.DisplayMember = "Display"
$form.Controls.Add($postList)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "標題"
$titleLabel.Location = New-Object System.Drawing.Point(415, 20)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$titleBox = New-Object System.Windows.Forms.TextBox
$titleBox.Location = New-Object System.Drawing.Point(470, 17)
$titleBox.Size = New-Object System.Drawing.Size(350, 28)
$titleBox.Anchor = "Top,Left,Right"
$form.Controls.Add($titleBox)

$seriesLabel = New-Object System.Windows.Forms.Label
$seriesLabel.Text = "專題"
$seriesLabel.Location = New-Object System.Drawing.Point(835, 20)
$seriesLabel.AutoSize = $true
$form.Controls.Add($seriesLabel)

$seriesBox = New-Object System.Windows.Forms.ComboBox
$seriesBox.Location = New-Object System.Drawing.Point(880, 17)
$seriesBox.Size = New-Object System.Drawing.Size(205, 28)
$seriesBox.DropDownStyle = "DropDown"
[void]$seriesBox.Items.AddRange($SeriesChoices)
$seriesBox.SelectedIndex = 0
$form.Controls.Add($seriesBox)

$dateLabel = New-Object System.Windows.Forms.Label
$dateLabel.Text = "日期"
$dateLabel.Location = New-Object System.Drawing.Point(415, 60)
$dateLabel.AutoSize = $true
$form.Controls.Add($dateLabel)

$datePicker = New-Object System.Windows.Forms.DateTimePicker
$datePicker.Location = New-Object System.Drawing.Point(470, 57)
$datePicker.Size = New-Object System.Drawing.Size(210, 28)
$datePicker.Format = "Custom"
$datePicker.CustomFormat = "yyyy-MM-dd HH:mm"
$form.Controls.Add($datePicker)

$categoryBox = New-Object System.Windows.Forms.ComboBox
$categoryBox.Location = New-Object System.Drawing.Point(700, 57)
$categoryBox.Size = New-Object System.Drawing.Size(145, 28)
$categoryBox.DropDownStyle = "DropDownList"
[void]$categoryBox.Items.AddRange(@("生活", "音樂", "天理教", "思考"))
$form.Controls.Add($categoryBox)

$slugBox = New-Object System.Windows.Forms.TextBox
$slugBox.Location = New-Object System.Drawing.Point(860, 57)
$slugBox.Size = New-Object System.Drawing.Size(225, 28)
$slugBox.Anchor = "Top,Left,Right"
$form.Controls.Add($slugBox)

$coverButton = New-Object System.Windows.Forms.Button
$coverButton.Text = "更換封面"
$coverButton.Location = New-Object System.Drawing.Point(415, 98)
$coverButton.Size = New-Object System.Drawing.Size(110, 34)
$form.Controls.Add($coverButton)

$imageButton = New-Object System.Windows.Forms.Button
$imageButton.Text = "在游標處加入圖片"
$imageButton.Location = New-Object System.Drawing.Point(540, 98)
$imageButton.Size = New-Object System.Drawing.Size(165, 34)
$form.Controls.Add($imageButton)

$imageStatus = New-Object System.Windows.Forms.Label
$imageStatus.Text = ""
$imageStatus.Location = New-Object System.Drawing.Point(720, 105)
$imageStatus.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($imageStatus)

$bodyBox = New-Object System.Windows.Forms.RichTextBox
$bodyBox.Location = New-Object System.Drawing.Point(415, 145)
$bodyBox.Size = New-Object System.Drawing.Size(670, 505)
$bodyBox.Anchor = "Top,Bottom,Left,Right"
$bodyBox.WordWrap = $true
$form.Controls.Add($bodyBox)

$previewTitle = New-Object System.Windows.Forms.Label
$previewTitle.Text = "文章圖片預覽"
$previewTitle.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 11, [System.Drawing.FontStyle]::Bold)
$previewTitle.Location = New-Object System.Drawing.Point(1105, 105)
$previewTitle.Size = New-Object System.Drawing.Size(225, 28)
$previewTitle.Anchor = "Top,Right"
$form.Controls.Add($previewTitle)

$imagePreviewList = New-Object System.Windows.Forms.ListBox
$imagePreviewList.Location = New-Object System.Drawing.Point(1105, 145)
$imagePreviewList.Size = New-Object System.Drawing.Size(235, 155)
$imagePreviewList.Anchor = "Top,Right"
$imagePreviewList.DisplayMember = "Display"
$form.Controls.Add($imagePreviewList)

$previewPicture = New-Object System.Windows.Forms.PictureBox
$previewPicture.Location = New-Object System.Drawing.Point(1105, 315)
$previewPicture.Size = New-Object System.Drawing.Size(235, 250)
$previewPicture.Anchor = "Top,Right"
$previewPicture.BorderStyle = "FixedSingle"
$previewPicture.SizeMode = "Zoom"
$form.Controls.Add($previewPicture)

$previewMessage = New-Object System.Windows.Forms.Label
$previewMessage.Location = New-Object System.Drawing.Point(1105, 575)
$previewMessage.Size = New-Object System.Drawing.Size(235, 55)
$previewMessage.Anchor = "Top,Right"
$previewMessage.TextAlign = "MiddleCenter"
$form.Controls.Add($previewMessage)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "備份並儲存修改"
$saveButton.Location = New-Object System.Drawing.Point(415, 670)
$saveButton.Size = New-Object System.Drawing.Size(165, 40)
$saveButton.Anchor = "Bottom,Left"
$form.Controls.Add($saveButton)

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "開啟本機預覽"
$previewButton.Location = New-Object System.Drawing.Point(595, 670)
$previewButton.Size = New-Object System.Drawing.Size(145, 40)
$previewButton.Anchor = "Bottom,Left"
$form.Controls.Add($previewButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "退出"
$exitButton.Location = New-Object System.Drawing.Point(755, 670)
$exitButton.Size = New-Object System.Drawing.Size(100, 40)
$exitButton.Anchor = "Bottom,Left"
$form.Controls.Add($exitButton)

$searchButton.Add_Click({ Load-List $searchBox.Text.Trim() })
$exitButton.Add_Click({ $form.Close() })
$imagePreviewList.Add_SelectedIndexChanged({
    if ($imagePreviewList.SelectedItem) { Show-ImagePreview ([string]$imagePreviewList.SelectedItem.Path) }
})

$postList.Add_SelectedIndexChanged({
    if (-not $postList.SelectedItem) { return }
    $script:SelectedPost = $postList.SelectedItem
    $parts = Split-Post $script:SelectedPost.Raw
    $titleBox.Text = Get-Value $parts.FrontMatter "title"
    $slugBox.Text = Get-Value $parts.FrontMatter "slug"
    $dateText = Get-Value $parts.FrontMatter "date"
    $parsedDate = Get-Date
    if ([datetime]::TryParse($dateText, [ref]$parsedDate)) { $datePicker.Value = $parsedDate }
    $categoryMatch = [regex]::Match($parts.FrontMatter, '(?ms)^categories:\s*\r?\n\s+-\s*["'']?([^"''\r\n]+)')
    $category = if ($categoryMatch.Success) { $categoryMatch.Groups[1].Value.Trim() } else { "生活" }
    $categoryBox.SelectedItem = $category
    if ($categoryBox.SelectedIndex -lt 0) { $categoryBox.SelectedIndex = 0 }
    $series = Get-Series $parts.FrontMatter
    $seriesBox.Text = $series
    $bodyBox.Text = $parts.Body.TrimEnd()
    $script:NewImages = @()
    $script:NewCover = $null
    $imageStatus.Text = "已載入：$($script:SelectedPost.Title)"
    Refresh-ImagePreviewList $parts.FrontMatter $parts.Body
})

$coverButton.Add_Click({
    if (-not $script:SelectedPost) { Show-ErrorMessage "請先選擇文章。"; return }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "圖片檔|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.heic;*.heif"
    if ($dialog.ShowDialog() -eq "OK") {
        $script:NewCover = $dialog.FileName
        $imageStatus.Text = "新封面：$([System.IO.Path]::GetFileName($script:NewCover))"
        $parts = Split-Post $script:SelectedPost.Raw
        Refresh-ImagePreviewList $parts.FrontMatter $bodyBox.Text
        Show-ImagePreview $script:NewCover
    }
})

$imageButton.Add_Click({
    if (-not $script:SelectedPost) { Show-ErrorMessage "請先選擇文章。"; return }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "圖片檔|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.heic;*.heif"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -eq "OK") {
        $markers = @()
        foreach ($file in $dialog.FileNames) {
            $script:NewImages += $file
            $markers += ("[[NEWIMAGE:{0:d3}]]" -f $script:NewImages.Count)
        }
        $bodyBox.SelectedText = "`r`n`r`n" + ($markers -join "`r`n`r`n") + "`r`n`r`n"
        $bodyBox.Focus()
        $imageStatus.Text = "已安排 $($script:NewImages.Count) 張新圖片"
        $parts = Split-Post $script:SelectedPost.Raw
        Refresh-ImagePreviewList $parts.FrontMatter $bodyBox.Text
        Show-ImagePreview ([string]$script:NewImages[-1])
    }
})

$saveButton.Add_Click({
    if (-not $script:SelectedPost) { Show-ErrorMessage "請先選擇文章。"; return }
    try {
        $postPath = [string]$script:SelectedPost.Path
        if ([string]::IsNullOrWhiteSpace($postPath) -or -not (Test-Path -LiteralPath $postPath -PathType Leaf)) {
            throw "找不到原文章檔案，請重新選取左側文章。"
        }
        $parts = Split-Post $script:SelectedPost.Raw
        $oldCover = Get-Value $parts.FrontMatter "cover"
        $front = Set-Value $parts.FrontMatter "title" $titleBox.Text.Trim()
        $front = Set-Value $front "date" $datePicker.Value.ToString("yyyy-MM-dd HH:mm:ss")
        if ($slugBox.Text.Trim()) { $front = Set-Value $front "slug" $slugBox.Text.Trim() }
        $front = Set-Category $front ([string]$categoryBox.SelectedItem)
        $front = Set-Series $front $seriesBox.Text.Trim()
        $body = Format-ArticleParagraphs $bodyBox.Text

        $assetKey = "edit-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        $assetDir = Join-Path $SiteRoot ("static\images\posts\" + $assetKey)
        $webDir = "/kirby1215/images/posts/" + $assetKey
        if ($script:NewCover -or $script:NewImages.Count -gt 0) { New-Item -ItemType Directory -Path $assetDir -Force | Out-Null }

        if ($script:NewCover) {
            $newCoverPath = [string]$script:NewCover
            if (-not (Test-Path -LiteralPath $newCoverPath -PathType Leaf)) { throw "找不到剛才選擇的封面：$newCoverPath" }
            $coverResult = Save-WebImage -Source $newCoverPath -DestinationBase (Join-Path $assetDir "cover")
            if (-not $coverResult -or [string]::IsNullOrWhiteSpace([string]$coverResult.FileName)) { throw "封面處理後沒有產生檔案。" }
            $newCoverWebPath = $webDir + "/" + $coverResult.FileName
            $front = Set-Value $front "cover" $newCoverWebPath
            $body = Set-CoverAsFirstImage -Body $body -OldCover $oldCover -NewCover $newCoverWebPath -Title $titleBox.Text.Trim()
        }

        for ($i = 0; $i -lt $script:NewImages.Count; $i++) {
            $baseName = "image-{0:d3}" -f ($i + 1)
            $result = Save-WebImage -Source ([string]$script:NewImages[$i]) -DestinationBase (Join-Path $assetDir $baseName)
            $marker = "[[NEWIMAGE:{0:d3}]]" -f ($i + 1)
            $markdown = "![$($titleBox.Text.Trim())]($webDir/$($result.FileName))"
            $body = $body.Replace($marker, $markdown)
        }

        $backup = Join-Path $SiteRoot ("migration-backups\edited-posts\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $postPath -Destination (Join-Path $backup ([System.IO.Path]::GetFileName($postPath)))

        $document = "---`r`n" + $front.Trim() + "`r`n---`r`n`r`n" + $body + "`r`n"
        [System.IO.File]::WriteAllText($postPath, $document, (New-Object System.Text.UTF8Encoding($false)))
        Show-Info "修改已儲存。`r`n`r`n原始版本備份於：`r`n$backup"
        Load-List $searchBox.Text.Trim()
    } catch { Show-ErrorMessage "儲存失敗：`r`n$($_.Exception.Message)" }
})

$previewButton.Add_Click({
    if (-not $script:SelectedPost) { Show-ErrorMessage "請先選擇文章。"; return }
    $date = $datePicker.Value
    $slug = $slugBox.Text.Trim()
    if (-not $slug) { $slug = $titleBox.Text.Trim() }
    $slug = ($slug -replace '\s+', '-' -replace '[\\/?#]+', '-').Trim('-')
    $url = "http://localhost:1313/kirby1215/{0}/{1}/{2}/{3}/" -f $date.ToString('yyyy'), $date.ToString('MM'), $date.ToString('dd'), [Uri]::EscapeDataString($slug)
    Start-Process $url
})

Load-List ""
[void]$form.ShowDialog()
