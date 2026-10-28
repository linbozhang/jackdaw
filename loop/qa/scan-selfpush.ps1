# Self-push operator scan (consolidated).
# Reports every #[operator] without allows_undo=false whose body reaches a
# self-push - directly, through a queued named impl, or through one level of
# called-local-fn indirection. Merge of the T03 rework round-1 scans
# (loop/t03r1-scan-selfpush.ps1, t03r1-scan-queued.ps1) and the QA indirect
# scan (loop/reports/t03r1qa-scan-indirect.ps1); the QA body is kept whole.

# QA independent scan: #[operator] fns WITHOUT allows_undo=false whose body
# (incl. one level of indirection: any called local fn in src that self-pushes)
# reaches push_executed / known self-push helpers.
$files = Get-ChildItem -Recurse -Include *.rs -Path src | Where-Object { $_.FullName -notmatch '\\tests\\' }
$texts = @{}
foreach ($f in $files) { $texts[$f.FullName] = [IO.File]::ReadAllText($f.FullName) }

# collect all fn definitions with their bodies
$fns = @{}   # name -> list of bodies
foreach ($f in $files) {
  $text = $texts[$f.FullName]
  foreach ($m in [regex]::Matches($text, '(?s)(?:pub(?:\(crate\))?\s+)?fn\s+(?<name>\w+)\s*\(')) {
    $name = $m.Groups['name'].Value
    $i = $text.IndexOf('{', $m.Index)
    if ($i -lt 0) { continue }
    $depth = 0; $end = -1
    for ($j = $i; $j -lt $text.Length; $j++) {
      $c = $text[$j]
      if ($c -eq '{') { $depth++ }
      elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
    }
    if ($end -lt 0) { continue }
    if (-not $fns.ContainsKey($name)) { $fns[$name] = @() }
    $fns[$name] += $text.Substring($i, $end - $i)
  }
}
$pushMarkers = 'push_executed|spawn_undoable|create_entity_in_world|reset_transform_selected|nudge_selected|rotate_selected_90'
$skip = @('if','else','for','while','match','warn','return','Some','None','Ok','Err','Box','Vec','assert','panic','clone','push','unwrap','expect','format','println','write','read','get','insert','remove','contains','iter','map','filter','collect','spawn','despawn','queue','execute','world','commands','history','stringify','vec','entry','resource','resource_mut','get_resource_mut','get_entity_mut','get_mut','get_or_insert','update','len','is_empty','new','from','to_string','to_owned','into','from_world','try_from','default')

function Body-Pushes([string]$body) {
  if ($body -match $pushMarkers) { return $true }
  # one level of indirection: any ident( call whose fn def exists and self-pushes
  $seen = @{}
  foreach ($cm in [regex]::Matches($body, '\b(?<id>[a-z_][a-z0-9_]*)\s*\(')) {
    $id = $cm.Groups['id'].Value
    if ($skip -contains $id) { continue }
    if ($seen.ContainsKey($id)) { continue }
    $seen[$id] = $true
    if ($fns.ContainsKey($id)) {
      foreach ($def in $fns[$id]) {
        if ($def -match 'push_executed') { return $true }
      }
    }
  }
  return $false
}

foreach ($f in $files) {
  $text = $texts[$f.FullName]
  foreach ($m in [regex]::Matches($text, '(?s)#\[operator\((?<attr>.*?)\)\]\s*(?:pub(?:\(crate\))?\s+)?fn\s+(?<name>\w+)')) {
    $attr = $m.Groups['attr'].Value
    $name = $m.Groups['name'].Value
    $idm = [regex]::Match($attr, 'id\s*=\s*"(?<id>[^"]+)"')
    $id = if ($idm.Success) { $idm.Groups['id'].Value } else { $name }
    if ($attr -match 'allows_undo\s*=\s*false') { continue }
    $i = $text.IndexOf('{', $m.Index + $m.Length)
    if ($i -lt 0) { continue }
    $depth = 0; $end = -1
    for ($j = $i; $j -lt $text.Length; $j++) {
      $c = $text[$j]
      if ($c -eq '{') { $depth++ }
      elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
    }
    if ($end -lt 0) { continue }
    $body = $text.Substring($i, $end - $i)
    if (Body-Pushes $body) {
      Write-Output ($f.Name + ': ' + $id)
    }
  }
}
