# Scan: #[operator] blocks without allows_undo=false whose fn body directly
# references a self-push marker. (Queued-closure pushes need manual follow-up.)
$files = Get-ChildItem -Recurse -Include *.rs -Path src | Where-Object { $_.FullName -notmatch '\\tests\\' }
foreach ($f in $files) {
  $text = [IO.File]::ReadAllText($f.FullName)
  $found = [regex]::Matches($text, '(?s)#\[operator\((?<attr>.*?)\)\]\s*(?:pub(?:\(crate\))?\s+)?fn\s+(?<name>\w+)')
  foreach ($m in $found) {
    $attr = $m.Groups['attr'].Value
    $name = $m.Groups['name'].Value
    if ($attr -match 'allows_undo\s*=\s*false') { continue }
    $start = $m.Index + $m.Length
    $i = $text.IndexOf('{', $start)
    if ($i -lt 0) { continue }
    $depth = 0; $bodyEnd = -1
    for ($j = $i; $j -lt $text.Length; $j++) {
      $c = $text[$j]
      if ($c -eq '{') { $depth++ }
      elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $bodyEnd = $j; break } }
    }
    if ($bodyEnd -lt 0) { continue }
    $body = $text.Substring($i, $bodyEnd - $i)
    if ($body -match 'push_executed|CommandHistory|spawn_undoable|create_entity_in_world|reset_transform_selected|nudge_selected|rotate_selected') {
      Write-Output ($f.Name + ': ' + $name)
    }
  }
}
