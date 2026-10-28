# Probe the recovery dialog's current UI state.
$ErrorActionPreference = 'Stop'
$Port = 15815
function Post([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 25
}
$t = (Post 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes
$script:hits = @()
function Walk($ns) {
    foreach ($n in @($ns)) {
        if ($n.text -and ($n.text -match 'Recovered|Restore|Discard|Preview|scene.bsn|recovered')) {
            $script:hits += [PSCustomObject]@{ entity = $n.entity; kind = $n.kind; text = $n.text; op = $n.operator; rect = ($n.rect -join ','); visible = $n.visible }
        }
        Walk @($n.children)
    }
}
Walk $t
Write-Output ("hits: " + @($script:hits).Count)
$script:hits | Select-Object -First 15 | ForEach-Object { Write-Output ("  e={0} kind={1} visible={2} op={3} text='{4}' rect={5}" -f $_.entity, $_.kind, $_.visible, $_.op, $_.text, $_.rect) }
