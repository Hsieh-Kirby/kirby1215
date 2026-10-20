param([string]$Workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference = 'Stop'
$feedPath = Join-Path $Workspace 'Takeout\Blogger\Blogs\教理讀書會籌備處\feed.atom'
$decisionPath = Join-Path $Workspace 'Takeout\review\decisions.json'
$outputRoot = Join-Path $Workspace 'content\posts\takeout'
if (-not (Test-Path $feedPath)) { throw "Missing feed: $feedPath" }
if (-not (Test-Path $decisionPath)) { throw "Missing decisions: $decisionPath" }

[xml]$xml = Get-Content -LiteralPath $feedPath -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('a','http://www.w3.org/2005/Atom')
$ns.AddNamespace('b','http://schemas.google.com/blogger/2018')
$decisions = @(Get-Content -LiteralPath $decisionPath -Raw | ConvertFrom-Json | Where-Object decision -eq '發佈')
$selected = @{}
foreach ($d in $decisions) { $selected[[int]$d.order] = $d }
$posts = @($xml.SelectNodes('/a:feed/a:entry[b:type="POST" and b:status="LIVE"]',$ns) | Sort-Object { [datetime]$_.SelectSingleNode('a:published',$ns).InnerText })

function Quote-Yaml([string]$Value) {
  return '"' + (($Value ?? '') -replace '\\','\\' -replace '"','\"' -replace "`r?`n",' ') + '"'
}
function New-YouTubeEmbed([string]$Id) {
  return "<div class=`"video-embed`" style=`"position:relative;padding-bottom:56.25%;height:0;overflow:hidden;margin:1.5rem 0;`">`n  <iframe src=`"https://www.youtube-nocookie.com/embed/$Id`" title=`"YouTube video player`" style=`"position:absolute;top:0;left:0;width:100%;height:100%;`" frameborder=`"0`" allow=`"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share`" allowfullscreen></iframe>`n</div>"
}
function Get-YouTubeId([string]$Text) {
  $m = [regex]::Match($Text,'(?i)(?:youtube(?:-nocookie)?\.com/(?:embed/|v/|watch\?(?:[^"''&<> ]*&)?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}
function Normalize-YouTube([string]$Html) {
  $embedded = New-Object 'System.Collections.Generic.HashSet[string]'
  $result = [regex]::Replace($Html,'(?is)<iframe\b[^>]*>.*?</iframe>',{
    param($m)
    $id = Get-YouTubeId $m.Value
    if ($id) { [void]$embedded.Add($id); return New-YouTubeEmbed $id }
    return $m.Value
  })
  $all = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($m in [regex]::Matches($Html,'(?i)(?:youtube(?:-nocookie)?\.com/(?:embed/|v/|watch\?(?:[^"''&<> ]*&)?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})')) { [void]$all.Add($m.Groups[1].Value) }
  $missing = @($all | Where-Object { -not $embedded.Contains($_) })
  if ($missing.Count) {
    $result += "`n<h2>相關影片</h2>`n"
    foreach ($id in $missing) { $result += (New-YouTubeEmbed $id) + "`n" }
  }
  return $result
}
function Normalize-LegacyFormatting([string]$Html) {
  $result = [regex]::Replace($Html, '(?is)<!--.*?-->', '')
  $result = [regex]::Replace($result, '(?is)<style\b[^>]*>.*?</style>', '')
  $result = [regex]::Replace($result, '(?is)<span\b[^>]*>', '')
  $result = [regex]::Replace($result, '(?i)</span>', '')
  $result = [regex]::Replace($result, '(?is)<font\b[^>]*>', '')
  $result = [regex]::Replace($result, '(?i)</font>', '')
  $result = [regex]::Replace($result, '(?i)\s+(?:style|face|lang)=(?:"[^"]*"|''[^'']*'')', '')
  $result = [regex]::Replace($result, '(?i)\s+class=(?:"Mso[^"]*"|''Mso[^'']*'')', '')
  $result = $result -replace '&nbsp;', ' '
  do {
    $before = $result
    $result = [regex]::Replace($result, '(?is)<p\b[^>]*>\s*(?:<br\s*/?>\s*)*</p>', '')
    $result = [regex]::Replace($result, '(?is)<div\b[^>]*>\s*(?:<br\s*/?>\s*)*</div>', '')
  } while ($result -ne $before)
  return $result
}
function Get-PlainText([string]$Html) {
  $text = $Html -replace '(?is)<script\b.*?</script>',' ' -replace '(?is)<style\b.*?</style>',' ' -replace '(?i)<br\s*/?>',"`n" -replace '(?is)<[^>]+>',' '
  return ([Net.WebUtility]::HtmlDecode($text) -replace '[\u00a0\s]+',' ').Trim()
}
function Get-Byline([string]$Title, [string]$Html) {
  $plain = Get-PlainText $Html
  $lead = $plain.Substring(0, [Math]::Min(600, $plain.Length))
  $m = [regex]::Match($lead, '^\(?作者應為\s*([^，。)]+)')
  if ($m.Success) { return '作者（原文註）：' + $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($lead, '(?:^|\s)作者\s*[:：]?\s*([^\s，。<>()]{2,10}?)\s*(女士|先生|教授|老師|會長)(?=\s|是|，|。|<|$)')
  if ($m.Success) { return '作者：' + ($m.Groups[1].Value + $m.Groups[2].Value).Trim() }
  $m = [regex]::Match($lead, '(?:^|\s)作者\s*[:：]?\s*([^\s，。<>()0-9]{2,12})')
  if ($m.Success) { return '作者：' + $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($Title, '講者\s*[:：]?\s*([^（()]+)')
  if ($m.Success) { return '講者：' + $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($Title, '[（(]講者\s*[:：]?\s*([^）)]+)')
  if ($m.Success) { return '講者：' + $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($Title + ' ' + $lead, '[（(]([^（）()]{2,20})翻譯及字幕[）)]')
  if ($m.Success) { return '翻譯及字幕：' + $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($Title + ' ' + $lead, '[（(]([^（）()]{2,20}?)(摘譯|翻譯|譯)[）)]')
  if ($m.Success) {
    $role = if ($m.Groups[2].Value -eq '摘譯') { '摘譯：' } else { '翻譯：' }
    return $role + $m.Groups[1].Value.Trim()
  }
  return ''
}
function Get-Cover([string]$Html, [string]$PostId, [string]$Workspace) {
  $m = [regex]::Match($Html, '(?is)<img\b[^>]*\bsrc=["'']([^"'']+)')
  if (-not $m.Success) { return '' }
  $src = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
  $data = [regex]::Match($src, '^data:(image/(?:jpeg|png|gif|webp));base64,(.+)$', 'IgnoreCase,Singleline')
  if ($data.Success) {
    $ext = switch ($data.Groups[1].Value.ToLowerInvariant()) { 'image/png' {'png'} 'image/gif' {'gif'} 'image/webp' {'webp'} default {'jpg'} }
    $relative = "images/takeout/tenristudy-$PostId-cover.$ext"
    $target = Join-Path $Workspace ('static\' + $relative.Replace('/','\'))
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    [IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($data.Groups[2].Value))
    return $relative
  }
  return $src
}
function Localize-Images([string]$Html, [string]$PostId, [string]$Workspace) {
  $imageIndex = 0
  return [regex]::Replace($Html, '(?is)(<img\b[^>]*\bsrc=["''])([^"'']+)(["''])', {
    param($m)
    $script:imageIndex++
    $src = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
    $mime = ''
    $bytes = $null
    $ext = 'jpg'
    $data = [regex]::Match($src, '^data:(image/(?:jpeg|png|gif|webp));base64,(.+)$', 'IgnoreCase,Singleline')
    if ($data.Success) {
      $mime = $data.Groups[1].Value.ToLowerInvariant()
      $bytes = [Convert]::FromBase64String($data.Groups[2].Value)
    } elseif ($src -match '^https?://') {
      $pathExt = [IO.Path]::GetExtension(([uri]$src).AbsolutePath).TrimStart('.').ToLowerInvariant()
      if ($pathExt -in @('jpg','jpeg','png','gif','webp')) { $ext = $pathExt }
    } else {
      return $m.Value
    }
    if ($mime) {
      $ext = switch ($mime) { 'image/png' {'png'} 'image/gif' {'gif'} 'image/webp' {'webp'} default {'jpg'} }
    }
    $relative = "images/takeout/tenristudy-$PostId-image-$('{0:d2}' -f $script:imageIndex).$ext"
    $publicPath = '/' + $relative
    $target = Join-Path $Workspace ('static\' + $relative.Replace('/','\'))
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    if (-not (Test-Path $target)) {
      if ($bytes) {
        [IO.File]::WriteAllBytes($target, $bytes)
      } else {
        $downloadUrl = $src -replace '/w\d+-h\d+(?:-[^/]+)?/', '/s0/'
        try {
          Invoke-WebRequest -Uri $downloadUrl -OutFile $target -Headers @{ 'User-Agent'='Mozilla/5.0' }
        } catch {
          if (Test-Path $target) { Remove-Item -LiteralPath $target -Force }
          Invoke-WebRequest -Uri $src -OutFile $target -Headers @{ 'User-Agent'='Mozilla/5.0' }
        }
      }
    }
    return $m.Groups[1].Value + $publicPath + $m.Groups[3].Value
  })
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$written = @()
for ($i=0; $i -lt $posts.Count; $i++) {
  $order = $i + 1
  if (-not $selected.ContainsKey($order)) { continue }
  $entry = $posts[$i]
  $title = $entry.SelectSingleNode('a:title',$ns).InnerText.Trim()
  $published = [datetimeoffset]::Parse($entry.SelectSingleNode('a:published',$ns).InnerText)
  $originalContent = $entry.SelectSingleNode('a:content',$ns).InnerText
  $idText = $entry.SelectSingleNode('a:id',$ns).InnerText
  $postId = ($idText -replace '^.*post-','')
  $localizedContent = Localize-Images $originalContent $postId $Workspace
  $content = Normalize-LegacyFormatting (Normalize-YouTube $localizedContent)
  $cover = Get-Cover $localizedContent $postId $Workspace
  $byline = Get-Byline $title $originalContent
  $filenameNode = $entry.SelectSingleNode('b:filename',$ns)
  $sourceUrl = if ($filenameNode -and $filenameNode.InnerText) { 'https://tenristudy.blogspot.com' + $filenameNode.InnerText } else { '' }
  $labels = @($entry.SelectNodes('a:category',$ns) | ForEach-Object { $_.GetAttribute('term') } | Where-Object { $_ })
  $front = @(
    '---',
    ('title: ' + (Quote-Yaml $title)),
    ('slug: ' + (Quote-Yaml ('tenristudy-' + $postId))),
    ('date: ' + (Quote-Yaml $published.ToString('yyyy-MM-dd HH:mm:sszzz'))),
    'draft: false',
    'categories:',
    '  - "天理教"',
    'original_tags:'
  )
  foreach ($label in $labels) { $front += ('  - ' + (Quote-Yaml $label)) }
  if ($cover) { $front += ('cover: ' + (Quote-Yaml $cover)) }
  if ($byline) { $front += ('byline: ' + (Quote-Yaml $byline)) }
  $front += @(
    ('original_url: ' + (Quote-Yaml $sourceUrl)),
    ('blogger_id: ' + (Quote-Yaml $postId)),
    'import_source: "Google Takeout"',
    '---',''
  )
  $path = Join-Path $outputRoot ("tenristudy-$postId.md")
  [IO.File]::WriteAllText($path, (($front -join "`n") + $content.Trim() + "`n"), [Text.UTF8Encoding]::new($false))
  $written += [pscustomobject]@{
    order=$order
    title=$title
    file=$path.Substring($Workspace.Length+1).Replace('\','/')
    images=([regex]::Matches($content,'src=["'']/images/takeout/').Count)
    youtube=([regex]::Matches($content,'youtube-nocookie\.com/embed/').Count)
  }
}
if ($written.Count -ne $decisions.Count) { throw "Expected $($decisions.Count) selected posts, wrote $($written.Count)." }
[IO.File]::WriteAllText((Join-Path $Workspace 'Takeout\review\import-result.json'), ($written | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Output "Imported $($written.Count) selected posts; local images: $(($written | Measure-Object images -Sum).Sum); YouTube embeds: $(($written | Measure-Object youtube -Sum).Sum)"
