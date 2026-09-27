Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PostsRoot = Join-Path $SiteRoot "content\posts"
$Categories = @("生活", "音樂", "天理教", "思考")
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Split-Post([string]$Text) {
    $match = [regex]::Match($Text, '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
    if (-not $match.Success) { throw "文章缺少正確的 YAML 開頭資料。" }
    [pscustomobject]@{ FrontMatter = $match.Groups[1].Value; Body = $match.Groups[2].Value }
}

function Get-Value([string]$FrontMatter, [string]$Name) {
    $match = [regex]::Match($FrontMatter, ('(?m)^{0}:\s*["'']?([^"''\r\n]+)' -f [regex]::Escape($Name)))
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ""
}

function Get-Category([string]$FrontMatter) {
    $match = [regex]::Match($FrontMatter, '(?ms)^categories:\s*\r?\n\s+-\s*["'']?([^"''\r\n]+)')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $inline = [regex]::Match($FrontMatter, '(?m)^categories:\s*\[\s*["'']?([^,"''\]]+)')
    if ($inline.Success) { return $inline.Groups[1].Value.Trim() }
    return "生活"
}

function Set-Category([string]$FrontMatter, [string]$Category) {
    $block = "categories:`r`n  - `"$Category`""
    $listPattern = '(?ms)^categories:\s*\r?\n(?:\s+-[^\r\n]*\r?\n?)*'
    if ([regex]::IsMatch($FrontMatter, $listPattern)) {
        return [regex]::Replace($FrontMatter, $listPattern, $block + "`r`n", 1)
    }
    $inlinePattern = '(?m)^categories:.*$'
    if ([regex]::IsMatch($FrontMatter, $inlinePattern)) {
        return [regex]::Replace($FrontMatter, $inlinePattern, $block, 1)
    }
    return $FrontMatter.TrimEnd() + "`r`n" + $block
}

$script:AllPosts = @()
Get-ChildItem -LiteralPath $PostsRoot -Filter '*.md' -File | ForEach-Object {
    try {
        $raw = [System.IO.File]::ReadAllText($_.FullName)
        $parts = Split-Post $raw
        $title = Get-Value $parts.FrontMatter 'title'
        if (-not $title) { $title = $_.BaseName }
        $script:AllPosts += [pscustomobject]@{
            Date = Get-Value $parts.FrontMatter 'date'
            Title = $title
            Category = Get-Category $parts.FrontMatter
            OriginalCategory = Get-Category $parts.FrontMatter
            Path = $_.FullName
        }
    } catch { }
}
$script:AllPosts = @($script:AllPosts | Sort-Object Date -Descending)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Kirby1215 批次修改分類'
$form.Size = New-Object System.Drawing.Size(1000, 760)
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = '在「分類」欄直接選擇；也可以選取多列，再用上方功能一次修改。最後按「備份並儲存全部修改」。'
$hint.Location = New-Object System.Drawing.Point(18, 16)
$hint.Size = New-Object System.Drawing.Size(930, 25)
$form.Controls.Add($hint)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(18, 50)
$searchBox.Size = New-Object System.Drawing.Size(245, 28)
$form.Controls.Add($searchBox)

$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Text = '搜尋標題'
$searchButton.Location = New-Object System.Drawing.Point(272, 47)
$searchButton.Size = New-Object System.Drawing.Size(95, 34)
$form.Controls.Add($searchButton)

$bulkBox = New-Object System.Windows.Forms.ComboBox
$bulkBox.Location = New-Object System.Drawing.Point(480, 50)
$bulkBox.Size = New-Object System.Drawing.Size(130, 28)
$bulkBox.DropDownStyle = 'DropDownList'
[void]$bulkBox.Items.AddRange($Categories)
$bulkBox.SelectedIndex = 0
$form.Controls.Add($bulkBox)

$bulkButton = New-Object System.Windows.Forms.Button
$bulkButton.Text = '套用到選取文章'
$bulkButton.Location = New-Object System.Drawing.Point(620, 47)
$bulkButton.Size = New-Object System.Drawing.Size(155, 34)
$form.Controls.Add($bulkButton)

$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Location = New-Object System.Drawing.Point(790, 55)
$countLabel.Size = New-Object System.Drawing.Size(170, 25)
$form.Controls.Add($countLabel)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(18, 92)
$grid.Size = New-Object System.Drawing.Size(945, 555)
$grid.Anchor = 'Top,Bottom,Left,Right'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.MultiSelect = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoGenerateColumns = $false
$form.Controls.Add($grid)

$dateCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dateCol.HeaderText = '日期'
$dateCol.Name = 'Date'
$dateCol.Width = 155
$dateCol.ReadOnly = $true
[void]$grid.Columns.Add($dateCol)

$titleCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$titleCol.HeaderText = '文章標題'
$titleCol.Name = 'Title'
$titleCol.AutoSizeMode = 'Fill'
$titleCol.ReadOnly = $true
[void]$grid.Columns.Add($titleCol)

$categoryCol = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
$categoryCol.HeaderText = '分類'
$categoryCol.Name = 'Category'
$categoryCol.Width = 140
$categoryCol.FlatStyle = 'Flat'
[void]$categoryCol.Items.AddRange($Categories)
[void]$grid.Columns.Add($categoryCol)

function Load-Grid([string]$Keyword) {
    $grid.Rows.Clear()
    $items = $script:AllPosts
    if (-not [string]::IsNullOrWhiteSpace($Keyword)) {
        $items = @($items | Where-Object { $_.Title -like "*$Keyword*" })
    }
    foreach ($post in $items) {
        $category = if ($Categories -contains $post.Category) { $post.Category } else { '生活' }
        $index = $grid.Rows.Add($post.Date, $post.Title, $category)
        $grid.Rows[$index].Tag = $post
    }
    $countLabel.Text = "顯示 $($grid.Rows.Count) 篇"
}

$searchButton.Add_Click({ Load-Grid $searchBox.Text.Trim() })
$searchBox.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Load-Grid $searchBox.Text.Trim(); $_.SuppressKeyPress = $true } })

$grid.Add_CellValueChanged({
    param($sender, $eventArgs)
    if ($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -eq $grid.Columns['Category'].Index) {
        $row = $grid.Rows[$eventArgs.RowIndex]
        if ($row.Tag) { $row.Tag.Category = [string]$row.Cells['Category'].Value }
    }
})
$grid.Add_CurrentCellDirtyStateChanged({ if ($grid.IsCurrentCellDirty) { $grid.CommitEdit('Commit') } })

$bulkButton.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('請先選取一篇或多篇文章。', '批次修改分類', 'OK', 'Information') | Out-Null
        return
    }
    foreach ($row in $grid.SelectedRows) {
        $row.Cells['Category'].Value = [string]$bulkBox.SelectedItem
        if ($row.Tag) { $row.Tag.Category = [string]$bulkBox.SelectedItem }
    }
})

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = '備份並儲存全部修改'
$saveButton.Location = New-Object System.Drawing.Point(18, 665)
$saveButton.Size = New-Object System.Drawing.Size(220, 42)
$saveButton.Anchor = 'Bottom,Left'
$form.Controls.Add($saveButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = '退出'
$exitButton.Location = New-Object System.Drawing.Point(843, 665)
$exitButton.Size = New-Object System.Drawing.Size(120, 42)
$exitButton.Anchor = 'Bottom,Right'
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

$saveButton.Add_Click({
    $changed = @($script:AllPosts | Where-Object { $_.Category -ne $_.OriginalCategory })
    if ($changed.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('目前沒有分類變更。', '批次修改分類', 'OK', 'Information') | Out-Null
        return
    }
    $backupRoot = Join-Path $SiteRoot ("migration-backups\before-category-edit-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    try {
        foreach ($post in $changed) {
            Copy-Item -LiteralPath $post.Path -Destination (Join-Path $backupRoot ([System.IO.Path]::GetFileName($post.Path))) -Force
            $raw = [System.IO.File]::ReadAllText($post.Path)
            $parts = Split-Post $raw
            $frontMatter = Set-Category $parts.FrontMatter $post.Category
            $updated = "---`r`n$frontMatter`r`n---`r`n`r`n" + $parts.Body.TrimStart("`r", "`n")
            [System.IO.File]::WriteAllText($post.Path, $updated, $Utf8NoBom)
            $post.OriginalCategory = $post.Category
        }
        [System.Windows.Forms.MessageBox]::Show("已修改 $($changed.Count) 篇文章。`r`n原檔備份：$backupRoot", '批次修改分類', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("儲存失敗：`r`n$($_.Exception.Message)", '批次修改分類', 'OK', 'Error') | Out-Null
    }
})

Load-Grid ''
[void]$form.ShowDialog()
