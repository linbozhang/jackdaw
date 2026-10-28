# Live-inspect rows matching '*Bloom*' with full JSON.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Rows {
    $j = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body (@{ jsonrpc = '2.0'; id = 1; method = 'world.query'; params = @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } } } | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 30
    $rows = $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 }
    foreach ($r in $rows) {
        $a = $r.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $r.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = [string]$r.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0] }
    }
}
$r = Rows | Where-Object { $_.text -like '*Bloom*' }
$r | ConvertTo-Json -Depth 3 | Write-Host
Write-Host '--- explicit property test:'
foreach ($row in @($r)) {
    Write-Host ("text='{0}' cx=[{1}] cy=[{2}] w=[{3}] hasProp={4}" -f $row.text, $row.cx, $row.cy, $row.w, ($null -ne $row.PSObject.Properties['cx']))
}
