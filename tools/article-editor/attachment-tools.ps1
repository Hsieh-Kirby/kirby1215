function Save-PdfAttachment([string]$Source, [string]$DestinationBase) {
    $sourceInfo = Get-Item -LiteralPath $Source
    if ($sourceInfo.Extension.ToLowerInvariant() -ne ".pdf") {
        throw "目前附件只支援 PDF 檔。"
    }
    if ($sourceInfo.Length -gt 25MB) {
        throw "PDF $($sourceInfo.Name) 超過 Cloudflare Pages 的 25 MB 單檔上限。"
    }

    $destination = $DestinationBase + ".pdf"
    Copy-Item -LiteralPath $Source -Destination $destination
    return [pscustomobject]@{
        FileName = [System.IO.Path]::GetFileName($destination)
        DisplayName = $sourceInfo.Name
        SizeMB = [math]::Round($sourceInfo.Length / 1MB, 2)
    }
}

function New-ImageLinkHtml([string]$WebPath, [string]$DisplayName) {
    $safePath = [System.Net.WebUtility]::HtmlEncode($WebPath)
    $safeName = [System.Net.WebUtility]::HtmlEncode($DisplayName)
    return "<a class=`"asset-link image-link`" href=`"$safePath`" target=`"_blank`" rel=`"noopener`">查看圖片：$safeName</a>"
}

function New-PdfLinksHtml([string]$WebPath, [string]$DisplayName) {
    $safePath = [System.Net.WebUtility]::HtmlEncode($WebPath)
    $safeName = [System.Net.WebUtility]::HtmlEncode($DisplayName)
    return "<span class=`"file-links`"><a href=`"$safePath`" target=`"_blank`" rel=`"noopener`">開啟 PDF：$safeName</a><a href=`"$safePath`" download>下載 PDF</a></span>"
}
