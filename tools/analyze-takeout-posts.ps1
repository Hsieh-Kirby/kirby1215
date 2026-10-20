param([string]$Workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference = 'Stop'
$takeout = Join-Path $Workspace 'Takeout'
$feed = Get-ChildItem $takeout -Recurse -Filter 'feed.atom' | Where-Object FullName -Match '\\Blogs\\' | Select-Object -First 1
if (-not $feed) { throw '找不到 Takeout Blogger Blogs/feed.atom' }
[xml]$xml = Get-Content -LiteralPath $feed.FullName -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('a','http://www.w3.org/2005/Atom')
$ns.AddNamespace('b','http://schemas.google.com/blogger/2018')
function Norm([string]$s) {
  $s = $s -replace '^\s*\d{4}[-_/]?\d{2}[-_/]?\d{2}\s*',''
  $s = $s -replace '^\s*\d{4}\s*',''
  $s = $s -replace '\(?\s*20\d{2}[-_/]\d{1,2}[-_/]\d{1,2}\s*\)?',''
  $s = $s -replace '\(?\s*20\d{2}[-_/]?\d{2,4}\s*\)?',''
  return (($s -replace '[\s　・･，,。.!！?？:：;；「」『』（）()【】\[\]~～_\-]','').ToLowerInvariant())
}
$site = @{}
Get-ChildItem (Join-Path $Workspace 'content') -Recurse -Filter '*.md' | ForEach-Object {
  $m = Select-String -LiteralPath $_.FullName -Pattern '^title:\s*["'']?(.*?)["'']?\s*$' | Select-Object -First 1
  if ($m) { $site[(Norm $m.Matches[0].Groups[1].Value)] = $_.FullName.Substring($Workspace.Length + 1).Replace('\','/') }
}
$records = @()
$i = 0
$posts = @($xml.SelectNodes('/a:feed/a:entry[b:type="POST" and b:status="LIVE"]',$ns) | Sort-Object { [datetime]$_.SelectSingleNode('a:published',$ns).InnerText })
foreach ($entry in $posts) {
  $i++
  $title = $entry.SelectSingleNode('a:title',$ns).InnerText.Trim()
  $published = [datetimeoffset]::Parse($entry.SelectSingleNode('a:published',$ns).InnerText).ToString('yyyy-MM-dd HH:mm')
  $content = $entry.SelectSingleNode('a:content',$ns).InnerText
  $cleanHtml = [regex]::Replace($content,'(?is)<(style|script)\b[^>]*>.*?</\1>',' ')
  $cleanHtml = [regex]::Replace($cleanHtml,'(?is)<!--.*?-->',' ')
  $plain = [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($cleanHtml,'(?is)<[^>]+>',' ')))
  $plain = [regex]::Replace($plain,'\s+',' ').Trim()
  $summary = if ($plain.Length -gt 160) { $plain.Substring(0,160) + '…' } else { $plain }
  $norm = Norm $title
  $sitePath = ''
  if ($site.ContainsKey($norm)) { $sitePath = $site[$norm] }
  else {
    foreach ($key in $site.Keys) {
      if ($norm.Length -ge 5 -and $key.Length -ge 5 -and ($key.Contains($norm) -or $norm.Contains($key))) { $sitePath = $site[$key]; break }
    }
  }
  $labels = @($entry.SelectNodes('a:category',$ns) | ForEach-Object { $_.GetAttribute('term') } | Where-Object { $_ }) -join '、'
  $youtube = New-Object System.Collections.Generic.HashSet[string]
  foreach ($match in [regex]::Matches($content,'(?i)(?:youtube(?:-nocookie)?\.com/(?:embed/|v/|watch\?(?:[^"''&<> ]*&)?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})')) { [void]$youtube.Add($match.Groups[1].Value) }
  if ($sitePath) { $recommendation = '已存在，不重複轉入'; $reason = 'kirby1215.tw 已有同名或高度相符文章。' }
  elseif ($youtube.Count -gt 0) { $recommendation = '優先轉入'; $reason = '目前網站未找到對應文章，且含可保留的 YouTube 影音內容。' }
  elseif ($plain.Length -ge 400) { $recommendation = '優先轉入'; $reason = '目前網站未找到對應文章，正文完整，具有教理、見證或歷史保存價值。' }
  elseif ($plain.Length -ge 120) { $recommendation = '可選轉入'; $reason = '目前網站未找到對應文章，但篇幅較短，可依保存需求決定。' }
  else { $recommendation = '暫不轉入'; $reason = '目前網站未找到對應文章，但正文過短或只有圖片；若要保留需先 OCR 或人工整理。' }
  $sourceUrl = ''
  foreach ($link in $entry.SelectNodes('a:link',$ns)) { if ($link.GetAttribute('rel') -eq 'alternate') { $sourceUrl = $link.GetAttribute('href'); break } }
  if (-not $sourceUrl) {
    $filenameNode = $entry.SelectSingleNode('b:filename',$ns)
    if ($filenameNode -and $filenameNode.InnerText) { $sourceUrl = 'https://tenristudy.blogspot.com' + $filenameNode.InnerText }
  }
  $records += [pscustomobject]@{ order=$i; recommendation=$recommendation; reason=$reason; decision='待決定'; published=$published; title=$title; labels=$labels; youtube_count=$youtube.Count; youtube_ids=($youtube -join ', '); image_count=[regex]::Matches($content,'(?i)<img\b').Count; text_chars=$plain.Length; summary=$summary; source_url=$sourceUrl; site_path=$sitePath }
}
$review = Join-Path $takeout 'review'
New-Item -ItemType Directory -Force -Path $review | Out-Null
[IO.File]::WriteAllText((Join-Path $review 'article-inventory.json'), ($records | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Output "Analyzed $($records.Count) posts; existing $(@($records | Where-Object recommendation -eq '已存在，不重複轉入').Count); new $(@($records | Where-Object recommendation -ne '已存在，不重複轉入').Count)"
