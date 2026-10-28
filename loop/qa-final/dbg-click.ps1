$ErrorActionPreference = 'Stop'
$Port = 15719
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port
function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5] }
    }
}
if ($args.Count -ge 2) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = [double]$args[0]; y = [double]$args[1]; action = 'click' } }) | Out-Null
    Start-Sleep -Milliseconds 500
    $rows = Get-UiRows | Where-Object { $_.cy -lt 260 -and $_.cy -gt 20 }
    Write-Host ("--- after click @(" + $args[0] + "," + $args[1] + ") rows below menu bar:")
    $rows | Sort-Object cy, cx | ForEach-Object { '{0,-42} ({1,8:N1},{2,6:N1})' -f $_.text, $_.cx, $_.cy }
}
