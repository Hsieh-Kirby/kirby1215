function Set-ArticleTextStyle([System.Windows.Forms.RichTextBox]$TextBox, [string]$Style) {
    if ([string]::IsNullOrWhiteSpace($TextBox.SelectedText)) {
        Show-Info "請先選取要設定的文字；副標題請選取整行。"
        return
    }
    $selected = $TextBox.SelectedText.Trim()
    if ($Style -in @('副標題', '小標題', '一般段落')) {
        $start = $TextBox.SelectionStart
        $end = $start + $TextBox.SelectionLength
        $text = $TextBox.Text
        while ($start -gt 0 -and $text[$start - 1] -ne "`n") { $start-- }
        while ($end -gt $start -and $text[$end - 1] -in @("`r", "`n")) { $end-- }
        while ($end -lt $text.Length -and $text[$end] -ne "`n") { $end++ }
        $TextBox.Select($start, $end - $start)
        $prefix = switch ($Style) { '副標題' { '## ' } '小標題' { '### ' } default { '' } }
        $lines = $TextBox.SelectedText.TrimEnd("`r", "`n") -split '\r?\n'
        $replacement = ($lines | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { '' }
            else { $prefix + ($_ -replace '^\s{0,3}#{1,6}\s+', '') }
        }) -join "`n"
        $TextBox.SelectedText = "`n" + $replacement + "`n"
    } elseif ($Style -in @('粗體', '斜體', '黑色字', '紅色字', '黃色字', '綠色字')) {
        $format = switch ($Style) {
            '粗體' { 'bold' }
            '斜體' { 'italic' }
            '黑色字' { 'black' }
            '紅色字' { 'red' }
            '黃色字' { 'yellow' }
            '綠色字' { 'green' }
        }
        $start = $TextBox.SelectionStart
        $replacement = "{{< textstyle $format >}}$selected{{< /textstyle >}}"
        $TextBox.SelectedText = $replacement
        $TextBox.Select($start, $replacement.Length)
    } else {
        $size = switch ($Style) { '放大 125%' { '125' } '放大 150%' { '150' } '放大 200%' { '200' } }
        if (-not $size) { return }
        $TextBox.SelectedText = "{{< textsize $size >}}$selected{{< /textsize >}}"
    }
    $TextBox.Focus()
}

function Add-ArticleTextToolbar($Form, $TextBox, [int]$X, [int]$Y) {
    $TextBox.HideSelection = $false
    $choices = New-Object System.Windows.Forms.ComboBox
    $choices.DropDownStyle = 'DropDownList'
    $choices.Location = New-Object System.Drawing.Point($X, $Y)
    $choices.Size = New-Object System.Drawing.Size(140, 30)
    $choices.Items.AddRange(@('副標題', '小標題', '一般段落', '放大 125%', '放大 150%', '放大 200%', '粗體', '斜體', '黑色字', '紅色字', '黃色字', '綠色字'))
    $choices.MaxDropDownItems = 12
    $choices.IntegralHeight = $false
    $choices.DropDownHeight = 320
    $choices.SelectedIndex = 0
    $Form.Controls.Add($choices)
    $choices.BringToFront()
    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = '套用字體'
    $apply.Location = New-Object System.Drawing.Point(($X + 145), $Y)
    $apply.Size = New-Object System.Drawing.Size(85, 30)
    $apply.Add_Click({ Set-ArticleTextStyle $TextBox ([string]$choices.SelectedItem) }.GetNewClosure())
    $Form.Controls.Add($apply)
    $apply.BringToFront()
}
