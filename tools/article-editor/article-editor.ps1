Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:CoverFile = $null
$script:BodyImages = @()
$script:LastPreviewUrl = "http://localhost:1313/kirby1215/"

function Show-Info([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 發文工具", "OK", "Information") | Out-Null
}

function Show-ErrorMessage([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "Kirby1215 發文工具", "OK", "Error") | Out-Null
}

function Convert-ToSafeFileName([string]$Value) {
    $name = $Value.Trim()
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace([string]$char, "-")
    }
    $name = $name.Trim(".", " ")
    if ([string]::IsNullOrWhiteSpace($name)) { return "新文章" }
    return $name
}

function Convert-ToSafeAssetKey([string]$Value, [datetime]$Date) {
    $ascii = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $ascii = $ascii.Trim("-")
    if ([string]::IsNullOrWhiteSpace($ascii)) {
        $ascii = "post-" + (Get-Date -Format "HHmmss")
    }
    return $Date.ToString("yyyyMMdd") + "-" + $ascii
}

function Escape-Yaml([string]$Value) {
    return $Value.Replace("\", "\\").Replace('"', '\"')
}

function Find-HeifConvert {
    $command = Get-Command heif-convert -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $known = "C:\Users\ky\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\libheif\libheif\bin\heif-convert.exe"
    if (Test-Path -LiteralPath $known) { return $known }
    return $null
}

function Save-WebImage([string]$Source, [string]$DestinationBase) {
    $targetBytes = 300KB
    $sourceInfo = Get-Item -LiteralPath $Source
    $extension = $sourceInfo.Extension.ToLowerInvariant()

    if ($extension -in @(".heic", ".heif")) {
        $converter = Find-HeifConvert
        if (-not $converter) {
            throw "找不到 HEIC 解碼器。請安裝 HEIF 圖像延伸模組，或先將 $($sourceInfo.Name) 轉成 JPG。"
        }
        $decodedFile = $DestinationBase + "-heic-source.jpg"
        try {
            & $converter $Source $decodedFile 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $decodedFile)) {
                throw "HEIC 圖片 $($sourceInfo.Name) 轉換失敗。"
            }
            $converted = Save-WebImage $decodedFile $DestinationBase
            $converted.Compressed = $true
            $converted.OriginalKB = [math]::Round($sourceInfo.Length / 1KB)
            return $converted
        } finally {
            if (Test-Path -LiteralPath $decodedFile) { Remove-Item -LiteralPath $decodedFile -Force }
        }
    }

    if ($sourceInfo.Length -le $targetBytes) {
        $destination = $DestinationBase + $extension
        Copy-Item -LiteralPath $Source -Destination $destination
        return [pscustomobject]@{
            FileName = [System.IO.Path]::GetFileName($destination)
            Compressed = $false
            OriginalKB = [math]::Round($sourceInfo.Length / 1KB)
            NewKB = [math]::Round($sourceInfo.Length / 1KB)
        }
    }

    if ($extension -notin @(".jpg", ".jpeg", ".png", ".bmp", ".gif")) {
        throw "圖片 $($sourceInfo.Name) 超過 300 KB，且 $extension 格式無法自動壓縮。請先轉成 JPG 或 PNG。"
    }

    $destination = $DestinationBase + ".jpg"
    $sourceImage = $null
    try {
        $sourceImage = [System.Drawing.Image]::FromFile($Source)
        $scale = [math]::Min(1.0, [math]::Min(1600.0 / $sourceImage.Width, 1600.0 / $sourceImage.Height))
        $width = [math]::Max(1, [int]($sourceImage.Width * $scale))
        $height = [math]::Max(1, [int]($sourceImage.Height * $scale))
        $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq "image/jpeg" } |
            Select-Object -First 1

        $finished = $false
        while (-not $finished) {
            $bitmap = New-Object System.Drawing.Bitmap($width, $height)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::White)
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.DrawImage($sourceImage, 0, 0, $width, $height)

                foreach ($quality in @(82, 72, 62, 52, 42)) {
                    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
                    $parameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
                    $parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                        [System.Drawing.Imaging.Encoder]::Quality,
                        [long]$quality
                    )
                    try {
                        $bitmap.Save($destination, $jpegEncoder, $parameters)
                    } finally {
                        $parameters.Dispose()
                    }
                    if ((Get-Item -LiteralPath $destination).Length -le $targetBytes) {
                        $finished = $true
                        break
                    }
                }
            } finally {
                $graphics.Dispose()
                $bitmap.Dispose()
            }

            if (-not $finished) {
                if ($width -le 640 -or $height -le 480) { $finished = $true }
                else {
                    $width = [math]::Max(1, [int]($width * 0.82))
                    $height = [math]::Max(1, [int]($height * 0.82))
                }
            }
        }
    } finally {
        if ($sourceImage) { $sourceImage.Dispose() }
    }

    $newInfo = Get-Item -LiteralPath $destination
    return [pscustomobject]@{
        FileName = $newInfo.Name
        Compressed = $true
        OriginalKB = [math]::Round($sourceInfo.Length / 1KB)
        NewKB = [math]::Round($newInfo.Length / 1KB)
    }
}

function Find-Hugo {
    $command = Get-Command hugo -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $known = "C:\Users\ky\AppData\Local\Microsoft\WinGet\Packages\Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe\hugo.exe"
    if (Test-Path -LiteralPath $known) { return $known }
    return $null
}

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

function Add-Log([string]$Message) {
    $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Show-DraftImagePreview([string]$ImagePath) {
    if ($draftPreviewPicture.Image) {
        $oldImage = $draftPreviewPicture.Image
        $draftPreviewPicture.Image = $null
        $oldImage.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        $draftPreviewMessage.Text = "尚未選擇圖片"
        return
    }
    try {
        $loaded = [System.Drawing.Image]::FromFile($ImagePath)
        try { $draftPreviewPicture.Image = New-Object System.Drawing.Bitmap($loaded) } finally { $loaded.Dispose() }
        $draftPreviewMessage.Text = [System.IO.Path]::GetFileName($ImagePath)
    } catch {
        $draftPreviewMessage.Text = "此格式儲存後可在網頁預覽"
    }
}

function Refresh-DraftImageList {
    $draftImageList.Items.Clear()
    if ($script:CoverFile) {
        [void]$draftImageList.Items.Add([pscustomobject]@{ Display = "封面：$([System.IO.Path]::GetFileName($script:CoverFile))"; Path = [string]$script:CoverFile })
    }
    for ($i = 0; $i -lt $script:BodyImages.Count; $i++) {
        $path = [string]$script:BodyImages[$i]
        [void]$draftImageList.Items.Add([pscustomobject]@{ Display = "內文 $($i + 1)：$([System.IO.Path]::GetFileName($path))"; Path = $path })
    }
    if ($draftImageList.Items.Count -gt 0 -and $draftImageList.SelectedIndex -lt 0) { $draftImageList.SelectedIndex = 0 }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Kirby1215 新增文章"
$form.Size = New-Object System.Drawing.Size(1320, 790)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10)
$form.MinimumSize = New-Object System.Drawing.Size(1180, 700)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "文章標題"
$titleLabel.Location = New-Object System.Drawing.Point(22, 20)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$titleBox = New-Object System.Windows.Forms.TextBox
$titleBox.Location = New-Object System.Drawing.Point(110, 17)
$titleBox.Size = New-Object System.Drawing.Size(570, 28)
$form.Controls.Add($titleBox)

$dateLabel = New-Object System.Windows.Forms.Label
$dateLabel.Text = "發布日期"
$dateLabel.Location = New-Object System.Drawing.Point(700, 20)
$dateLabel.AutoSize = $true
$form.Controls.Add($dateLabel)

$datePicker = New-Object System.Windows.Forms.DateTimePicker
$datePicker.Location = New-Object System.Drawing.Point(785, 17)
$datePicker.Size = New-Object System.Drawing.Size(205, 28)
$datePicker.Format = "Custom"
$datePicker.CustomFormat = "yyyy-MM-dd HH:mm"
$form.Controls.Add($datePicker)

$categoryLabel = New-Object System.Windows.Forms.Label
$categoryLabel.Text = "分類"
$categoryLabel.Location = New-Object System.Drawing.Point(22, 60)
$categoryLabel.AutoSize = $true
$form.Controls.Add($categoryLabel)

$categoryBox = New-Object System.Windows.Forms.ComboBox
$categoryBox.Location = New-Object System.Drawing.Point(110, 57)
$categoryBox.Size = New-Object System.Drawing.Size(170, 28)
$categoryBox.DropDownStyle = "DropDownList"
[void]$categoryBox.Items.AddRange(@("生活", "音樂", "天理教", "思考"))
$categoryBox.SelectedIndex = 0
$form.Controls.Add($categoryBox)

$slugLabel = New-Object System.Windows.Forms.Label
$slugLabel.Text = "網址名稱（可留空）"
$slugLabel.Location = New-Object System.Drawing.Point(310, 60)
$slugLabel.AutoSize = $true
$form.Controls.Add($slugLabel)

$slugBox = New-Object System.Windows.Forms.TextBox
$slugBox.Location = New-Object System.Drawing.Point(465, 57)
$slugBox.Size = New-Object System.Drawing.Size(300, 28)
$form.Controls.Add($slugBox)

$coverButton = New-Object System.Windows.Forms.Button
$coverButton.Text = "選擇封面圖片"
$coverButton.Location = New-Object System.Drawing.Point(22, 100)
$coverButton.Size = New-Object System.Drawing.Size(135, 34)
$form.Controls.Add($coverButton)

$coverStatus = New-Object System.Windows.Forms.Label
$coverStatus.Text = "尚未選擇（可省略）"
$coverStatus.Location = New-Object System.Drawing.Point(170, 107)
$coverStatus.Size = New-Object System.Drawing.Size(400, 24)
$form.Controls.Add($coverStatus)

$imagesButton = New-Object System.Windows.Forms.Button
$imagesButton.Text = "在游標處加入圖片"
$imagesButton.Location = New-Object System.Drawing.Point(600, 100)
$imagesButton.Size = New-Object System.Drawing.Size(135, 34)
$form.Controls.Add($imagesButton)

$imagesStatus = New-Object System.Windows.Forms.Label
$imagesStatus.Text = "先在正文選位置，再按左側按鈕"
$imagesStatus.Location = New-Object System.Drawing.Point(750, 107)
$imagesStatus.Size = New-Object System.Drawing.Size(220, 24)
$form.Controls.Add($imagesStatus)

$contentLabel = New-Object System.Windows.Forms.Label
$contentLabel.Text = "文章正文（可直接貼上純文字或 Markdown）"
$contentLabel.Location = New-Object System.Drawing.Point(22, 150)
$contentLabel.AutoSize = $true
$form.Controls.Add($contentLabel)

$contentBox = New-Object System.Windows.Forms.RichTextBox
$contentBox.Location = New-Object System.Drawing.Point(22, 177)
$contentBox.Size = New-Object System.Drawing.Size(968, 370)
$contentBox.Anchor = "Top,Bottom,Left,Right"
$contentBox.AcceptsTab = $true
$contentBox.WordWrap = $true
$form.Controls.Add($contentBox)

$draftPreviewTitle = New-Object System.Windows.Forms.Label
$draftPreviewTitle.Text = "插入圖片預覽"
$draftPreviewTitle.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 11, [System.Drawing.FontStyle]::Bold)
$draftPreviewTitle.Location = New-Object System.Drawing.Point(1010, 150)
$draftPreviewTitle.Size = New-Object System.Drawing.Size(260, 28)
$draftPreviewTitle.Anchor = "Top,Right"
$form.Controls.Add($draftPreviewTitle)

$draftImageList = New-Object System.Windows.Forms.ListBox
$draftImageList.Location = New-Object System.Drawing.Point(1010, 182)
$draftImageList.Size = New-Object System.Drawing.Size(270, 135)
$draftImageList.Anchor = "Top,Right"
$draftImageList.DisplayMember = "Display"
$form.Controls.Add($draftImageList)

$draftPreviewPicture = New-Object System.Windows.Forms.PictureBox
$draftPreviewPicture.Location = New-Object System.Drawing.Point(1010, 330)
$draftPreviewPicture.Size = New-Object System.Drawing.Size(270, 210)
$draftPreviewPicture.Anchor = "Top,Right"
$draftPreviewPicture.BorderStyle = "FixedSingle"
$draftPreviewPicture.SizeMode = "Zoom"
$form.Controls.Add($draftPreviewPicture)

$draftPreviewMessage = New-Object System.Windows.Forms.Label
$draftPreviewMessage.Text = "尚未選擇圖片"
$draftPreviewMessage.Location = New-Object System.Drawing.Point(1010, 545)
$draftPreviewMessage.Size = New-Object System.Drawing.Size(270, 45)
$draftPreviewMessage.Anchor = "Top,Right"
$draftPreviewMessage.TextAlign = "MiddleCenter"
$form.Controls.Add($draftPreviewMessage)

$createButton = New-Object System.Windows.Forms.Button
$createButton.Text = "建立文章"
$createButton.Location = New-Object System.Drawing.Point(22, 565)
$createButton.Size = New-Object System.Drawing.Size(125, 38)
$createButton.Anchor = "Bottom,Left"
$form.Controls.Add($createButton)

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "啟動本機預覽"
$previewButton.Location = New-Object System.Drawing.Point(160, 565)
$previewButton.Size = New-Object System.Drawing.Size(145, 38)
$previewButton.Anchor = "Bottom,Left"
$form.Controls.Add($previewButton)

$publishButton = New-Object System.Windows.Forms.Button
$publishButton.Text = "發布到 GitHub／Cloudflare"
$publishButton.Location = New-Object System.Drawing.Point(318, 565)
$publishButton.Size = New-Object System.Drawing.Size(145, 38)
$publishButton.Anchor = "Bottom,Left"
$form.Controls.Add($publishButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = "開啟文章資料夾"
$openFolderButton.Location = New-Object System.Drawing.Point(476, 565)
$openFolderButton.Size = New-Object System.Drawing.Size(145, 38)
$openFolderButton.Anchor = "Bottom,Left"
$form.Controls.Add($openFolderButton)

$deleteArticleButton = New-Object System.Windows.Forms.Button
$deleteArticleButton.Text = "刪除文章"
$deleteArticleButton.Location = New-Object System.Drawing.Point(634, 565)
$deleteArticleButton.Size = New-Object System.Drawing.Size(125, 38)
$deleteArticleButton.Anchor = "Bottom,Left"
$form.Controls.Add($deleteArticleButton)

$editArticleButton = New-Object System.Windows.Forms.Button
$editArticleButton.Text = "編輯文章"
$editArticleButton.Location = New-Object System.Drawing.Point(772, 565)
$editArticleButton.Size = New-Object System.Drawing.Size(125, 38)
$editArticleButton.Anchor = "Bottom,Left"
$form.Controls.Add($editArticleButton)

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(22, 620)
$logBox.Size = New-Object System.Drawing.Size(968, 105)
$logBox.Anchor = "Bottom,Left,Right"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(247, 244, 237)
$form.Controls.Add($logBox)

$draftImageList.Add_SelectedIndexChanged({
    if ($draftImageList.SelectedItem) { Show-DraftImagePreview ([string]$draftImageList.SelectedItem.Path) }
})

$coverButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "選擇封面圖片"
    $dialog.Filter = "圖片檔|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.heic;*.heif"
    if ($dialog.ShowDialog() -eq "OK") {
        $script:CoverFile = $dialog.FileName
        $coverStatus.Text = [System.IO.Path]::GetFileName($script:CoverFile)
        Refresh-DraftImageList
        Show-DraftImagePreview $script:CoverFile
    }
})

$imagesButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "選擇內文圖片（可複選）"
    $dialog.Filter = "圖片檔|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.heic;*.heif"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -eq "OK") {
        $markers = New-Object System.Collections.Generic.List[string]
        foreach ($selectedFile in $dialog.FileNames) {
            $script:BodyImages += $selectedFile
            $imageNumber = $script:BodyImages.Count
            $markers.Add("[[IMAGE:{0:d3}]]" -f $imageNumber)
        }
        $insertText = "`r`n`r`n" + ($markers -join "`r`n`r`n") + "`r`n`r`n"
        $contentBox.SelectedText = $insertText
        $imagesStatus.Text = "已安排 $($script:BodyImages.Count) 張；可移動圖片標記"
        Refresh-DraftImageList
        Show-DraftImagePreview ([string]$script:BodyImages[-1])
        $contentBox.Focus()
    }
})

$createButton.Add_Click({
    try {
        $title = $titleBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($title)) {
            Show-ErrorMessage "請輸入文章標題。"
            return
        }

        $date = $datePicker.Value
        $category = [string]$categoryBox.SelectedItem
        $slug = $slugBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $title }
        $slug = ($slug -replace "\s+", "-" -replace "[\\/?#]+", "-").Trim("-")

        $fileName = (Convert-ToSafeFileName $title) + ".md"
        $postPath = Join-Path $SiteRoot ("content\posts\" + $fileName)
        if (Test-Path -LiteralPath $postPath) {
            Show-ErrorMessage "同名文章已存在：`r`n$postPath`r`n`r`n請修改標題或先備份舊檔。"
            return
        }

        $assetKey = Convert-ToSafeAssetKey $slug $date
        $assetDirectory = Join-Path $SiteRoot ("static\images\posts\" + $assetKey)
        $webDirectory = "/kirby1215/images/posts/" + $assetKey
        $coverWebPath = $null
        $imageMarkdown = New-Object System.Collections.Generic.List[string]

        if ($script:CoverFile -or $script:BodyImages.Count -gt 0) {
            New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
        }

        if ($script:CoverFile) {
            $coverResult = Save-WebImage $script:CoverFile (Join-Path $assetDirectory "cover")
            $coverName = $coverResult.FileName
            $coverWebPath = $webDirectory + "/" + $coverName
            if ($coverResult.Compressed) {
                Add-Log "封面已自動壓縮：$($coverResult.OriginalKB) KB → $($coverResult.NewKB) KB"
            }
        }

        $number = 1
        foreach ($source in $script:BodyImages) {
            $imageBaseName = "image-{0:d3}" -f $number
            $imageResult = Save-WebImage $source (Join-Path $assetDirectory $imageBaseName)
            $imageName = $imageResult.FileName
            $imageMarkdown.Add("![$(Escape-Yaml $title)]($webDirectory/$imageName)")
            if ($imageResult.Compressed) {
                Add-Log "$imageName 已自動壓縮：$($imageResult.OriginalKB) KB → $($imageResult.NewKB) KB"
            }
            $number++
        }

        $frontMatter = @(
            "---"
            "title: `"$(Escape-Yaml $title)`""
            "date: `"$($date.ToString('yyyy-MM-dd HH:mm:ss'))`""
            "slug: `"$(Escape-Yaml $slug)`""
            "categories:"
            "  - `"$(Escape-Yaml $category)`""
        )
        if ($coverWebPath) { $frontMatter += "cover: `"$coverWebPath`"" }
        $frontMatter += "---"

        $body = $contentBox.Text.Trim()
        for ($imageIndex = 0; $imageIndex -lt $imageMarkdown.Count; $imageIndex++) {
            $marker = "[[IMAGE:{0:d3}]]" -f ($imageIndex + 1)
            if ($body.Contains($marker)) {
                $body = $body.Replace($marker, $imageMarkdown[$imageIndex])
            } else {
                if ($body) { $body += "`r`n`r`n" }
                $body += $imageMarkdown[$imageIndex]
            }
        }

        # 封面同時也是文章正文的第一張圖片。
        if ($coverWebPath) {
            $coverMarkdown = "![$(Escape-Yaml $title)]($coverWebPath)"
            $body = if ($body) { $coverMarkdown + "`r`n`r`n" + $body.TrimStart() } else { $coverMarkdown }
        }

        $document = ($frontMatter -join "`r`n") + "`r`n`r`n" + $body + "`r`n"
        [System.IO.File]::WriteAllText($postPath, $document, (New-Object System.Text.UTF8Encoding($false)))

        $encodedSlug = [System.Uri]::EscapeDataString($slug)
        $script:LastPreviewUrl = "http://localhost:1313/kirby1215/{0}/{1}/{2}/{3}/" -f `
            $date.ToString("yyyy"), $date.ToString("MM"), $date.ToString("dd"), $encodedSlug

        Add-Log "已建立文章：$fileName"
        Add-Log "預覽網址：$script:LastPreviewUrl"
        if ($coverWebPath) { Add-Log "已加入封面，並設為文章第一張圖片。" }
        if ($imageMarkdown.Count -gt 0) { Add-Log "已加入 $($imageMarkdown.Count) 張內文圖片。" }
        Show-Info "文章建立完成。`r`n`r`n$postPath`r`n`r`n接著請按「啟動本機預覽」檢查。"
    } catch {
        Show-ErrorMessage "建立文章失敗：`r`n$($_.Exception.Message)"
    }
})

$previewButton.Add_Click({
    $hugo = Find-Hugo
    if (-not $hugo) {
        Show-ErrorMessage "找不到 Hugo。請確認 Hugo 已安裝。"
        return
    }
    Start-Process -FilePath $hugo -ArgumentList @('server','-D','--disableFastRender') -WorkingDirectory $SiteRoot -WindowStyle Hidden
    Start-Sleep -Seconds 2
    Start-Process $script:LastPreviewUrl
    Add-Log "已啟動 Hugo 預覽：$script:LastPreviewUrl"
    Add-Log "黑色視窗請保持開啟。"
})

$openFolderButton.Add_Click({
    Start-Process explorer.exe (Join-Path $SiteRoot "content\posts")
})

$deleteArticleButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $PSScriptRoot "delete-article.ps1")
    )
})

$editArticleButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $PSScriptRoot "edit-article.ps1")
    )
})

$publishButton.Add_Click({
    try {
        $hugo = Find-Hugo
        if (-not $hugo) {
            Show-ErrorMessage "找不到 Hugo，無法進行發布前檢查。"
            return
        }
        if (-not (Test-Path -LiteralPath (Join-Path $SiteRoot ".git"))) {
            Show-ErrorMessage "這個網站尚未連接 GitHub（找不到 .git）。"
            return
        }
        $git = Find-Git
        if (-not $git) {
            Show-ErrorMessage "找不到 Git，無法發布到 GitHub。"
            return
        }

        Add-Log "正在執行發布前完整建置檢查……"
        Push-Location $SiteRoot
        try {
            & $hugo --minify 2>&1 | ForEach-Object { Add-Log ([string]$_) }
            if ($LASTEXITCODE -ne 0) {
                Show-ErrorMessage "Hugo 建置失敗，已停止發布。請先處理記錄中的錯誤。"
                return
            }

            $changes = (& $git status --short 2>&1) -join "`r`n"
            if ([string]::IsNullOrWhiteSpace($changes)) {
                Show-Info "目前沒有需要發布的新變更。"
                return
            }

            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Hugo 檢查通過。即將把以下變更發布到 GitHub：`r`n`r`n$changes`r`n`r`n確定要繼續嗎？",
                "確認發布",
                "YesNo",
                "Question"
            )
            if ($answer -ne "Yes") {
                Add-Log "已取消發布。"
                return
            }

            Ensure-GitIdentity $git
            & $git add --all
            & $git commit -m ("新增文章與網站更新 " + (Get-Date -Format "yyyy-MM-dd HH:mm")) 2>&1 | ForEach-Object { Add-Log ([string]$_) }
            if ($LASTEXITCODE -ne 0) {
                Show-ErrorMessage "Git 建立版本失敗，尚未上傳。"
                return
            }
            & $git push 2>&1 | ForEach-Object { Add-Log ([string]$_) }
            if ($LASTEXITCODE -ne 0) {
                Show-ErrorMessage "GitHub 上傳失敗。文章仍安全保存在本機。"
                return
            }
            Add-Log "GitHub 上傳完成；Cloudflare 正在自動更新。"
            Show-Info "網站資料已上傳 GitHub，Cloudflare Pages 正在自動更新公開網站。"
        } finally {
            Pop-Location
        }
    } catch {
        Show-ErrorMessage "發布失敗：`r`n$($_.Exception.Message)"
    }
})

Add-Log "網站位置：$SiteRoot"
Add-Log "請填寫文章，建立後先使用本機預覽確認。"
[void]$form.ShowDialog()
