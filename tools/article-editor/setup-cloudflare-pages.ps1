Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object Windows.Forms.Form
$form.Text = "Kirby1215 Cloudflare Pages 同步設定"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object Drawing.Size(720, 610)
$form.MinimumSize = New-Object Drawing.Size(720, 610)
$form.Font = New-Object Drawing.Font("Microsoft JhengHei UI", 10)

$intro = New-Object Windows.Forms.Label
$intro.Location = New-Object Drawing.Point(24, 20)
$intro.Size = New-Object Drawing.Size(650, 55)
$intro.Text = "這項設定只需完成一次。完成後，每次使用「發布到GitHub與Cloudflare」，Cloudflare Pages 都會從 GitHub 自動同步更新。"
$form.Controls.Add($intro)

$steps = New-Object Windows.Forms.TextBox
$steps.Location = New-Object Drawing.Point(24, 82)
$steps.Size = New-Object Drawing.Size(650, 350)
$steps.Multiline = $true
$steps.ReadOnly = $true
$steps.ScrollBars = "Vertical"
$steps.BackColor = [Drawing.Color]::White
$steps.Text = @"
1. 按下面「開啟 Cloudflare」並登入。

2. 進入 Workers & Pages，選擇：
   Create application → Pages → Connect to Git

3. 授權 GitHub，選擇：
   Hsieh-Kirby / kirby1215

4. 建置設定請填：
   Production branch：main
   Build command：hugo --gc --minify -b `$CF_PAGES_URL
   Build output directory：public
   Root directory：留白

5. Environment variables 新增：
   HUGO_VERSION = 0.166.0

6. 按 Save and Deploy。第一次成功後，以後不需再設定。

注意：Cloudflare 網址會是「專案名稱.pages.dev」。原來的 GitHub Pages 網址仍會保留，兩邊會同時更新。
"@
$form.Controls.Add($steps)

$copy = New-Object Windows.Forms.Button
$copy.Location = New-Object Drawing.Point(24, 450)
$copy.Size = New-Object Drawing.Size(205, 45)
$copy.Text = "複製建置指令"
$copy.Add_Click({
    [Windows.Forms.Clipboard]::SetText('hugo --gc --minify -b $CF_PAGES_URL')
    [Windows.Forms.MessageBox]::Show("已複製建置指令。", "完成", "OK", "Information") | Out-Null
})
$form.Controls.Add($copy)

$cloudflare = New-Object Windows.Forms.Button
$cloudflare.Location = New-Object Drawing.Point(244, 450)
$cloudflare.Size = New-Object Drawing.Size(205, 45)
$cloudflare.Text = "開啟 Cloudflare"
$cloudflare.Add_Click({ Start-Process "https://dash.cloudflare.com/" })
$form.Controls.Add($cloudflare)

$github = New-Object Windows.Forms.Button
$github.Location = New-Object Drawing.Point(464, 450)
$github.Size = New-Object Drawing.Size(205, 45)
$github.Text = "開啟 GitHub repository"
$github.Add_Click({ Start-Process "https://github.com/Hsieh-Kirby/kirby1215" })
$form.Controls.Add($github)

$close = New-Object Windows.Forms.Button
$close.Location = New-Object Drawing.Point(244, 510)
$close.Size = New-Object Drawing.Size(205, 40)
$close.Text = "完成／關閉"
$close.Add_Click({ $form.Close() })
$form.Controls.Add($close)

[void]$form.ShowDialog()
