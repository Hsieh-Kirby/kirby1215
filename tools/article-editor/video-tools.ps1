function Save-WebVideo([string]$Source, [string]$DestinationBase) {
    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "找不到選擇的影片：$Source"
    }

    $sourceInfo = Get-Item -LiteralPath $Source
    $extension = $sourceInfo.Extension.ToLowerInvariant()
    if ($extension -notin @(".mp4", ".webm", ".ogg")) {
        throw "不支援 $extension 影片。請使用 MP4、WebM 或 OGG；建議使用 MP4。"
    }

    # GitHub 一般 Git 儲存庫的單檔硬限制為 100 MB，預留一些空間以避免 push 才失敗。
    $maximumBytes = 95MB
    if ($sourceInfo.Length -gt $maximumBytes) {
        $sizeMB = [math]::Round($sourceInfo.Length / 1MB, 1)
        throw "影片 $($sourceInfo.Name) 為 $sizeMB MB，超過本站 95 MB 上限。請先壓縮影片再上傳。"
    }

    $destination = $DestinationBase + $extension
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    return [pscustomobject]@{
        FileName = [System.IO.Path]::GetFileName($destination)
        SizeMB = [math]::Round($sourceInfo.Length / 1MB, 1)
    }
}

function New-VideoHtml([string]$WebPath, [string]$Title) {
    $safePath = [System.Net.WebUtility]::HtmlEncode($WebPath)
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
    return @"
<figure class="article-video">
<video controls preload="metadata" playsinline title="$safeTitle">
<source src="$safePath">
您的瀏覽器無法播放此影片。<a href="$safePath">下載影片</a>
</video>
</figure>
"@.Trim()
}

function Get-YouTubeVideoId([string]$Url) {
    $value = $Url.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw "請貼上 YouTube 影片網址。" }
    foreach ($pattern in @(
        '(?i)(?:youtube\.com/watch\?(?:[^#\s]*&)?v=)([A-Za-z0-9_-]{11})',
        '(?i)(?:youtu\.be/)([A-Za-z0-9_-]{11})',
        '(?i)(?:youtube\.com/(?:embed|shorts|live)/)([A-Za-z0-9_-]{11})'
    )) {
        $match = [regex]::Match($value, $pattern)
        if ($match.Success) { return $match.Groups[1].Value }
    }
    throw "無法辨識這個 YouTube 網址。請從瀏覽器或 YouTube 的分享功能複製影片網址。"
}

function New-YouTubeHtml([string]$Url, [string]$Title) {
    $videoId = Get-YouTubeVideoId $Url
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
    return @"
<figure class="youtube-video">
<iframe src="https://www.youtube-nocookie.com/embed/$videoId" title="$safeTitle" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
</figure>
"@.Trim()
}
