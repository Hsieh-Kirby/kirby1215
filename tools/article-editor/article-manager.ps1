Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Kirby1215 文章管理"
$form.Size = New-Object System.Drawing.Size(520, 475)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 11)

$title = New-Object System.Windows.Forms.Label
$title.Text = "請選擇要進行的工作"
$title.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 18)
$title.Location = New-Object System.Drawing.Point(35, 28)
$title.AutoSize = $true
$form.Controls.Add($title)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "完成一項工作並關閉視窗後，可回到這裡選擇其他功能。"
$hint.Location = New-Object System.Drawing.Point(38, 72)
$hint.Size = New-Object System.Drawing.Size(440, 28)
$form.Controls.Add($hint)

function Add-ActionButton([string]$Text, [int]$Y, [string]$ScriptName) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point(40, $Y)
    $button.Size = New-Object System.Drawing.Size(425, 48)
    $button.Add_Click({
        $scriptPath = Join-Path $PSScriptRoot $ScriptName
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptPath + '"'))
    }.GetNewClosure())
    $form.Controls.Add($button)
}

Add-ActionButton "新增文章" 112 "article-editor.ps1"
Add-ActionButton "編輯已發布文章" 168 "edit-article.ps1"
Add-ActionButton "刪除文章與專用圖片" 224 "delete-article.ps1"
Add-ActionButton "批次修改文章分類" 280 "bulk-category.ps1"
Add-ActionButton "發布網站到 GitHub" 336 "publish-site.ps1"

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "退出"
$exitButton.Location = New-Object System.Drawing.Point(365, 396)
$exitButton.Size = New-Object System.Drawing.Size(100, 34)
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

[void]$form.ShowDialog()
