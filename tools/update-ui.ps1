# Shared styling for the standalone updater, after the player has closed.
# Kept separate from installation so the windows can be previewed without changing files.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function New-CrtUpdateWindow([string]$Root, [string]$Version) {
    $panel = [Drawing.ColorTranslator]::FromHtml('#17191e')
    $accent = [Drawing.ColorTranslator]::FromHtml('#ff9148')
    $muted = [Drawing.ColorTranslator]::FromHtml('#9a9fa9')
    $form = New-Object Windows.Forms.Form
    $form.Text = 'CRT-mpv'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(560, 232)
    $form.BackColor = $panel
    $form.ForeColor = [Drawing.ColorTranslator]::FromHtml('#eceef2')
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.AutoScaleMode = 'Dpi'
    $form.TopMost = $true
    $ico = Join-Path $Root 'assets\crt-mpv.ico'
    if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object Drawing.Icon $ico }
    $mark = New-Object Windows.Forms.Panel
    $mark.SetBounds(24, 26, 3, 37)
    $mark.BackColor = $accent
    $title = New-Object Windows.Forms.Label
    $title.SetBounds(39, 22, 490, 35)
    $title.Font = New-Object Drawing.Font('Segoe UI', 17, [Drawing.FontStyle]::Bold)
    $title.Text = 'Updating CRT-mpv'
    $subtitle = New-Object Windows.Forms.Label
    $subtitle.SetBounds(40, 60, 490, 24)
    $subtitle.ForeColor = $muted
    $subtitle.Text = "Installing version $Version"
    $status = New-Object Windows.Forms.Label
    $status.SetBounds(26, 108, 508, 42)
    $status.AutoEllipsis = $true
    $track = New-Object Windows.Forms.Panel
    $track.SetBounds(26, 158, 508, 5)
    $track.BackColor = [Drawing.ColorTranslator]::FromHtml('#363940')
    $fill = New-Object Windows.Forms.Panel
    $fill.SetBounds(0, 0, 0, 5)
    $fill.BackColor = $accent
    $track.Controls.Add($fill)
    $footer = New-Object Windows.Forms.Label
    $footer.SetBounds(26, 184, 508, 24)
    $footer.ForeColor = $muted
    $footer.Font = New-Object Drawing.Font('Segoe UI', 9)
    $footer.Text = 'Your library, settings and playback position are kept.'
    $form.Controls.AddRange(@($mark, $title, $subtitle, $status, $track, $footer))
    return [pscustomobject]@{ Form=$form; Title=$title; Subtitle=$subtitle; Status=$status;
        Track=$track; Fill=$fill; Footer=$footer; LastPaint=[datetime]::MinValue; LastText='' }
}

function Set-CrtUpdateStatus($Ui, [string]$Text, [int]$Percent = -1) {
    $now = [datetime]::UtcNow
    # Download callbacks can arrive for every 64 KB. Paint at most ten times per second.
    if (($Text -eq $Ui.LastText -or ($Percent -ge 0 -and $Percent -lt 100)) -and
        ($now - $Ui.LastPaint).TotalMilliseconds -lt 100) { return }
    $Ui.LastText = $Text
    $Ui.LastPaint = $now
    $Ui.Status.Text = $Text
    if ($Percent -ge 0) {
        $value = [Math]::Max(0, [Math]::Min(100, $Percent))
        $Ui.Fill.Left = 0
        $Ui.Fill.Width = [int]($Ui.Track.ClientSize.Width * $value / 100)
        $Ui.Footer.Text = "Your library, settings and playback position are kept.    $value%"
    } else {
        # A quiet accent indicates work without an always-running animation timer.
        $Ui.Fill.Left = 0
        $Ui.Fill.Width = [int]($Ui.Track.ClientSize.Width / 4)
        $Ui.Footer.Text = 'Your library, settings and playback position are kept.'
    }
    [Windows.Forms.Application]::DoEvents()
}

function Show-CrtUpdateFailure($Ui, [string]$Version, [string]$Detail) {
    $form = $Ui.Form
    $form.Hide()
    $form.ClientSize = New-Object Drawing.Size(560, 360)
    $form.ControlBox = $true
    $Ui.Title.Text = 'Update could not finish'
    $Ui.Subtitle.Text = "CRT-mpv $Version was not installed."
    $Ui.Status.Text = 'The previous version has been kept.'
    $Ui.Status.Height = 26
    $Ui.Track.Hide()
    $Ui.Footer.Hide()
    $details = New-Object Windows.Forms.TextBox
    $details.SetBounds(26, 145, 508, 128)
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = 'Vertical'
    $details.BorderStyle = 'None'
    $details.BackColor = $form.BackColor
    $details.ForeColor = [Drawing.ColorTranslator]::FromHtml('#9a9fa9')
    $details.Text = $Detail
    $button = New-Object Windows.Forms.Button
    $button.SetBounds(400, 298, 134, 36)
    $button.Text = 'Close'
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [Drawing.ColorTranslator]::FromHtml('#ff9148')
    $button.ForeColor = [Drawing.ColorTranslator]::FromHtml('#20150d')
    $button.DialogResult = 'OK'
    $form.AcceptButton = $button
    $form.CancelButton = $button
    $form.Controls.AddRange(@($details, $button))
    $button.Select()
    [void]$form.ShowDialog()
}
