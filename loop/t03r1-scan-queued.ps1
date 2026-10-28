# Scan: default-true operators whose queued fn target self-pushes.
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
    # a bare named fn queued: commands.queue(some_fn)
    $qs = [regex]::Matches($body, 'commands\.queue\(\s*(?<target>[a-z_][a-z0-9_]*)\s*\)')
    foreach ($q in $qs) {
      $target = $q.Groups['target'].Value
      # find that fn's body anywhere in src and check for a push marker
      foreach ($f2 in $files) {
        $t2 = [IO.File]::ReadAllText($f2.FullName)
        $fm = [regex]::Match($t2, '(?s)fn\s+' + $target + '\s*\(')
        if (-not $fm.Success) { continue }
        $i2 = $t2.IndexOf('{', $fm.Index)
        $depth2 = 0; $end2 = -1
        for ($j2 = $i2; $j2 -lt $t2.Length; $j2++) {
          $c2 = $t2[$j2]
          if ($c2 -eq '{') { $depth2++ }
          elseif ($c2 -eq '}') { $depth2--; if ($depth2 -eq 0) { $end2 = $j2; break } }
        }
        if ($end2 -lt 0) { continue }
        $b2 = $t2.Substring($i2, $end2 - $i2)
        if ($b2 -match 'push_executed') {
          Write-Output ($f.Name + ': ' + $name + '  ->  ' + $f2.Name + ':' + $target)
        }
        break
      }
    }
  }
}
