param(
  [string]$Workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$blogspotRoot = Join-Path $Workspace 'blogspot'
$feed = Get-ChildItem (Join-Path $blogspotRoot 'Takeout1') -Recurse -Filter 'feed.atom' |
  Where-Object { $_.FullName -match '\\Blogs\\' } |
  Select-Object -First 1
if (-not $feed) { throw '找不到 Blogger Blogs/feed.atom' }

$reviewRoot = Join-Path $blogspotRoot 'review'
$articleRoot = Join-Path $reviewRoot 'articles'
New-Item -ItemType Directory -Force -Path $articleRoot | Out-Null
$videoEmbedPath = Join-Path $blogspotRoot 'video-embeds.json'
$videoEmbeds = @{}
if (Test-Path $videoEmbedPath) {
  $videoMap = Get-Content -LiteralPath $videoEmbedPath -Raw | ConvertFrom-Json
  foreach ($property in $videoMap.PSObject.Properties) { $videoEmbeds[$property.Name] = [string]$property.Value }
}

[xml]$xml = Get-Content -LiteralPath $feed.FullName -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('a', 'http://www.w3.org/2005/Atom')
$ns.AddNamespace('b', 'http://schemas.google.com/blogger/2018')

function Get-NodeText([System.Xml.XmlNode]$Node, [string]$XPath) {
  $found = $Node.SelectSingleNode($XPath, $ns)
  if ($found) { return $found.InnerText }
  return ''
}

function Get-YouTubeId([string]$Text) {
  $patterns = @(
    '(?i)(?:youtube(?:-nocookie)?\.com/(?:embed/|v/|watch\?(?:[^"''&<> ]*&)?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})',
    '(?i)[?&]video_id=([A-Za-z0-9_-]{6,})'
  )
  foreach ($pattern in $patterns) {
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
  }
  return $null
}

function New-YouTubeEmbed([string]$Id) {
  return @"
<div class="video-embed" style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;margin:1.5rem 0;">
  <iframe src="https://www.youtube-nocookie.com/embed/$Id" title="YouTube video player" style="position:absolute;top:0;left:0;width:100%;height:100%;" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
</div>
"@
}

function Normalize-YouTube([string]$Html) {
  $result = [regex]::Replace($Html, '(?is)<object\b[^>]*>.*?</object>', {
    param($m)
    $id = Get-YouTubeId $m.Value
    if ($id) { return New-YouTubeEmbed $id }
    return $m.Value
  })
  $result = [regex]::Replace($result, '(?is)<iframe\b[^>]*>.*?</iframe>', {
    param($m)
    $id = Get-YouTubeId $m.Value
    if ($id) { return New-YouTubeEmbed $id }
    return $m.Value
  })
  return $result
}

function Normalize-BloggerVideo([string]$Html) {
  return [regex]::Replace($Html, '(?is)<object\b[^>]*class=["'']BLOG_video_class["''][^>]*contentid=["'']([^"'']+)["''][^>]*>.*?</object>', {
    param($m)
    $contentId = $m.Groups[1].Value
    if (-not $videoEmbeds.ContainsKey($contentId)) { return $m.Value }
    $iframe = $videoEmbeds[$contentId]
    $iframe = [regex]::Replace($iframe, '\s+(width|height)=["''][^"'']*["'']', '')
    $iframe = $iframe -replace '<iframe ', '<iframe style="position:absolute;top:0;left:0;width:100%;height:100%;" '
    return '<div class="video-embed blogger-video" style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;margin:1.5rem 0;">' + "`n  " + $iframe + "`n</div>"
  })
}

function Quote-Yaml([string]$Value) {
  return '"' + ($Value -replace '\\', '\\' -replace '"', '\"' -replace "`r?`n", ' ') + '"'
}

function Safe-FilePart([string]$Value) {
  $safe = $Value -replace '[<>:"/\\|?*\x00-\x1F]', '-'
  $safe = $safe.Trim().TrimEnd('.')
  if ($safe.Length -gt 70) { $safe = $safe.Substring(0, 70).Trim() }
  if (-not $safe) { $safe = 'untitled' }
  return $safe
}

$taipei = [System.TimeZoneInfo]::FindSystemTimeZoneById('Taipei Standard Time')
$posts = @($xml.SelectNodes('/a:feed/a:entry[b:type="POST" and b:status="LIVE"]', $ns))
$records = @()
$counter = 0

foreach ($entry in ($posts | Sort-Object { [datetime](Get-NodeText $_ 'a:published') })) {
  $counter++
  $title = (Get-NodeText $entry 'a:title').Trim()
  $publishedRaw = Get-NodeText $entry 'a:published'
  $published = [datetimeoffset]::Parse($publishedRaw)
  $localDate = [System.TimeZoneInfo]::ConvertTime($published, $taipei)
  $content = Get-NodeText $entry 'a:content'
  $youtubeIds = New-Object System.Collections.Generic.HashSet[string]
  foreach ($match in [regex]::Matches($content, '(?i)(?:youtube(?:-nocookie)?\.com/(?:embed/|v/|watch\?(?:[^"''&<> ]*&)?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})')) {
    [void]$youtubeIds.Add($match.Groups[1].Value)
  }
  $bloggerVideoCount = [regex]::Matches($content, '(?is)<object\b[^>]*class=["'']BLOG_video_class["'']').Count
  $normalized = Normalize-BloggerVideo $content
  $normalized = Normalize-YouTube $normalized
  $imageCount = [regex]::Matches($normalized, '(?i)<img\b').Count
  $labels = @($entry.SelectNodes('a:category', $ns) | ForEach-Object { $_.GetAttribute('term') } | Where-Object { $_ })
  $sourceUrl = ''
  foreach ($link in $entry.SelectNodes('a:link', $ns)) {
    if ($link.GetAttribute('rel') -eq 'alternate') { $sourceUrl = $link.GetAttribute('href'); break }
  }
  $sourceId = (Get-NodeText $entry 'a:id') -replace '^.*post-', ''
  $filename = ('{0:D3}-{1}-{2}.md' -f $counter, $localDate.ToString('yyyy-MM-dd'), (Safe-FilePart $title))
  $frontMatter = @(
    '---',
    ('title: ' + (Quote-Yaml $title)),
    ('date: ' + $localDate.ToString('yyyy-MM-ddTHH:mm:sszzz')),
    'draft: true',
    'blogspot_review: true',
    ('blogger_id: ' + (Quote-Yaml $sourceId)),
    ('blogger_url: ' + (Quote-Yaml $sourceUrl)),
    'categories:',
    '  - "待分類"',
    'tags:'
  )
  foreach ($label in $labels) { $frontMatter += ('  - ' + (Quote-Yaml $label)) }
  $frontMatter += '---'
  $articleText = ($frontMatter -join "`n") + "`n`n" + $normalized.Trim() + "`n"
  [System.IO.File]::WriteAllText((Join-Path $articleRoot $filename), $articleText, [System.Text.UTF8Encoding]::new($false))

  $plain = [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($normalized, '(?is)<[^>]+>', ' ')))
  $plain = [regex]::Replace($plain, '\s+', ' ').Trim()
  if ($plain.Length -gt 140) { $plain = $plain.Substring(0, 140) + '…' }
  $records += [pscustomobject]@{
    order = $counter
    decision = '待決定'
    published = $localDate.ToString('yyyy-MM-dd HH:mm')
    title = $title
    labels = ($labels -join '、')
    youtube_count = $youtubeIds.Count
    blogger_video_count = $bloggerVideoCount
    image_count = $imageCount
    summary = $plain
    source_url = $sourceUrl
    blogger_id = $sourceId
    review_file = ('articles/' + $filename)
    notes = ''
  }
}

$inventoryPath = Join-Path $reviewRoot 'article-inventory.json'
[System.IO.File]::WriteAllText($inventoryPath, ($records | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))

$readme = @"
# Blogspot 文章待審區

這裡共有 $($records.Count) 篇從 Blogger 匯出的已發布文章。`articles/` 內的檔案均標記為 `draft: true`，而且位於 Hugo `content/` 之外，不會出現在 kirby1215.tw。

請在 `blogspot-文章發布選擇表.xlsx` 的「發布選擇」欄選擇：

- `發佈`：之後匯入網站。
- `不發佈`：保留於備份，但不上站。
- `待決定`：暫不處理。

YouTube 的舊式 object/iframe 嵌入已轉成響應式 iframe，使用 `youtube-nocookie.com`。網站的 Hugo 設定已允許安全渲染原始 HTML，因此正式匯入後可直接播放。

注意：Blogger 自有影片（不是 YouTube）另外標示於表格中，需要在正式發布階段確認本地 MP4 對應關係。
"@
[System.IO.File]::WriteAllText((Join-Path $reviewRoot 'README.md'), $readme, [System.Text.UTF8Encoding]::new($false))

Write-Output "Prepared $($records.Count) posts in $reviewRoot"
