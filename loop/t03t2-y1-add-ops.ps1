# T03-T2 Y1: add allows_undo = false to the self-pushing entity.add.* ops and
# the 15 transform ops. Files are CRLF.
$ErrorActionPreference = 'Stop'
$nl = "`r`n"

$path = 'src\entity_ops.rs'
$text = [IO.File]::ReadAllText($path)
$names = 'cube','sphere','point_light','directional_light','spot_light','camera','camera_rig','empty','plane','cylinder','wedge','cone','pyramid','animation_player','audio_source','fog_volume','reflection_probe','spawn_point','zone_transition','network_room','terrain'
$count = 0
foreach ($n in $names) {
  $pattern = '#\[operator\(id = "entity\.add\.' + $n + '", label = "([^"]+)"\)\]'
  $replacement = "#[operator(${nl}    id = `"entity.add.$n`",${nl}    label = `"`$1`",${nl}    allows_undo = false${nl})]"
  $new = [regex]::Replace($text, $pattern, $replacement)
  if ($new -ne $text) { $count++ }
  $text = $new
}
[IO.File]::WriteAllText($path, $text)
Write-Output "entity.add converted: $count"

$path2 = 'src\transform_ops.rs'
$text2 = [IO.File]::ReadAllText($path2)
$count2 = 0
$ids = 'transform.reset_position','transform.reset_rotation','transform.reset_scale',
       'transform.rotate_90_yaw_ccw','transform.rotate_90_yaw_cw','transform.rotate_90_pitch_ccw','transform.rotate_90_pitch_cw','transform.rotate_90_roll_ccw','transform.rotate_90_roll_cw',
       'transform.nudge_x_neg','transform.nudge_x_pos','transform.nudge_y_neg','transform.nudge_y_pos','transform.nudge_z_neg','transform.nudge_z_pos'
foreach ($id in $ids) {
  $pattern3 = '(id = "' + [regex]::Escape($id) + '",' + $nl + '    label = "[^"]+",)' + $nl + '(    is_available = can_)'
  $replacement3 = "`$1${nl}    allows_undo = false,${nl}`$2"
  $new2 = [regex]::Replace($text2, $pattern3, $replacement3)
  if ($new2 -ne $text2) { $count2++ }
  $text2 = $new2
}
[IO.File]::WriteAllText($path2, $text2)
Write-Output "transform converted: $count2"
