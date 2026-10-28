# **DEPRECATED (2026-10-25, T-QT-T2)**: the BRP `ui_tree` method replaces this
# whole script-side method (world.query Text/UiGlobalTransform + coordinate
# math). Keep only for diffing against ui_tree output or talking to an editor
# build older than the 2026-10-24 tools merge. See manual.md section 7.
# Dump UI text nodes (Text + ComputedNode + UiGlobalTransform) to a JSON file.
# Usage: uitext.ps1 [-Port 15703] [-OutFile path] [-MaxY 9999]
param([int]$Port = 15703, [string]$OutFile = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e\uitext-live.json', [double]$MaxY = 99999)
$body = '{"jsonrpc":"2.0","id":1,"method":"world.query","params":{"data":{"components":["bevy_ui::widget::text::Text","bevy_ui::ui_node::ComputedNode","bevy_ui::ui_transform::UiGlobalTransform"]}}}'
$w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 30
$j = [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
$rows = $j.result | Where-Object {
    $_.components.'bevy_ui::ui_transform::UiGlobalTransform'[5] -lt $MaxY -and
    $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 -and
    $_.components.'bevy_ui::widget::text::Text'.Length -lt 60
} | ForEach-Object {
    $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
    $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
    [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [math]::Round($a[4],1); cy = [math]::Round($a[5],1); w = $s[0]; h = $s[1] }
}
$rows | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 $OutFile
Write-Host ("rows: " + @($rows).Count + " -> " + $OutFile)
