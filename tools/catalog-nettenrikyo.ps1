param(
    [string]$Source = "nettenrikyo",
    [string]$Output = "nettenrikyo/_organizing/content-inventory.csv"
)

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$outputPath = Join-Path (Get-Location) $Output
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Get-Category([string]$relativePath) {
    $top = ($relativePath -split '[\\/]')[0]
    switch -Regex ($top) {
        '^triple$|^triple\.html$' { return '01-scriptures' }
        '^teaching$|^teaching\.html$' { return '02-doctrine' }
        '^speech$|^speech\.html$' { return '03-sermons' }
        '^article$|^article\.html$|^article-old\.html$' { return '04-articles' }
        '^window$|^happy$' { return '05-notes-and-series' }
        '^resource\.html$|^files$' { return '06-resources' }
        '^old design$' { return '90-archive' }
        '^images$' { return '91-shared-assets' }
        default { return '00-entry-and-unclassified' }
    }
}

function Get-HtmlTitle([string]$path) {
    if ([IO.Path]::GetExtension($path) -ne '.html') { return '' }
    $text = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ($text -match '(?is)<title[^>]*>\s*(.*?)\s*</title>') {
        return ([regex]::Replace($Matches[1], '<[^>]+>', '') -replace '\s+', ' ').Trim()
    }
    return ''
}

$rows = Get-ChildItem -LiteralPath $sourcePath -Recurse -File |
    Where-Object {
        $candidateRelative = $_.FullName.Substring($sourcePath.Length + 1)
        $candidateRelative -notmatch '^_organizing[\\/]' -and
        $candidateRelative -notmatch '^_'
    } |
    ForEach-Object {
        $relative = $_.FullName.Substring($sourcePath.Length + 1).Replace('\', '/')
        $extension = $_.Extension.ToLowerInvariant()
        $kind = switch ($extension) {
            '.html' { 'HTML' }
            '.pdf'  { 'PDF' }
            '.docx' { 'DOCX' }
            '.pptx' { 'PPTX' }
            '.jpg'  { 'Image' }
            '.jpeg' { 'Image' }
            '.png'  { 'Image' }
            '.gif'  { 'Image' }
            default { 'Other' }
        }
        [PSCustomObject]@{
            category = Get-Category $relative
            type = $kind
            title = Get-HtmlTitle $_.FullName
            source_path = $relative
            size_bytes = $_.Length
            modified_at = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            status = 'pending-review'
            notes = ''
        }
    }

$rows | Sort-Object category, source_path |
    Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding UTF8

Write-Output "Created $($rows.Count) inventory rows: $outputPath"
