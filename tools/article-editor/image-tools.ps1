function Find-HeifConvert {
    $command = Get-Command heif-convert -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $known = "C:\Users\ky\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\libheif\libheif\bin\heif-convert.exe"
    if (Test-Path -LiteralPath $known) { return $known }
    return $null
}

function Save-WebImage([string]$Source, [string]$DestinationBase) {
    if ([string]::IsNullOrWhiteSpace($Source)) { throw "沒有收到圖片路徑，請重新選擇圖片。" }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "找不到圖片：$Source" }
    if ([string]::IsNullOrWhiteSpace($DestinationBase)) { throw "圖片儲存位置是空的。" }

    $targetBytes = 300KB
    $sourceInfo = Get-Item -LiteralPath $Source
    $extension = $sourceInfo.Extension.ToLowerInvariant()

    if ($extension -in @(".heic", ".heif")) {
        $converter = Find-HeifConvert
        if (-not $converter) { throw "找不到 HEIC 解碼器，請先把圖片轉成 JPG。" }
        $decodedFile = $DestinationBase + "-heic-source.jpg"
        try {
            & $converter $Source $decodedFile 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $decodedFile)) { throw "HEIC 圖片轉換失敗：$($sourceInfo.Name)" }
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
        Copy-Item -LiteralPath $Source -Destination $destination -Force
        return [pscustomobject]@{ FileName = [IO.Path]::GetFileName($destination); Compressed = $false; OriginalKB = [math]::Round($sourceInfo.Length / 1KB); NewKB = [math]::Round($sourceInfo.Length / 1KB) }
    }

    if ($extension -notin @(".jpg", ".jpeg", ".png", ".bmp", ".gif")) { throw "圖片格式 $extension 無法自動壓縮，請先轉成 JPG 或 PNG。" }

    $destination = $DestinationBase + ".jpg"
    $sourceImage = $null
    try {
        $sourceImage = [Drawing.Image]::FromFile($Source)
        $scale = [math]::Min(1.0, [math]::Min(1600.0 / $sourceImage.Width, 1600.0 / $sourceImage.Height))
        $width = [math]::Max(1, [int]($sourceImage.Width * $scale))
        $height = [math]::Max(1, [int]($sourceImage.Height * $scale))
        $jpegEncoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq "image/jpeg" | Select-Object -First 1
        $finished = $false
        while (-not $finished) {
            $bitmap = New-Object Drawing.Bitmap($width, $height)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::White)
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($sourceImage, 0, 0, $width, $height)
                foreach ($quality in @(82, 72, 62, 52, 42)) {
                    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
                    $parameters = New-Object Drawing.Imaging.EncoderParameters(1)
                    $parameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]$quality)
                    try { $bitmap.Save($destination, $jpegEncoder, $parameters) } finally { $parameters.Dispose() }
                    if ((Get-Item -LiteralPath $destination).Length -le $targetBytes) { $finished = $true; break }
                }
            } finally { $graphics.Dispose(); $bitmap.Dispose() }
            if (-not $finished) {
                if ($width -le 640 -or $height -le 480) { $finished = $true }
                else { $width = [math]::Max(1, [int]($width * 0.82)); $height = [math]::Max(1, [int]($height * 0.82)) }
            }
        }
    } finally { if ($sourceImage) { $sourceImage.Dispose() } }

    $newInfo = Get-Item -LiteralPath $destination
    return [pscustomobject]@{ FileName = $newInfo.Name; Compressed = $true; OriginalKB = [math]::Round($sourceInfo.Length / 1KB); NewKB = [math]::Round($newInfo.Length / 1KB) }
}
