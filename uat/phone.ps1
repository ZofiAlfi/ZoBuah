# Helper pengujian POS di HP lewat adb.
# Cara pakai:
#   .\phone.ps1 ui                     -> tampilkan widget yang terbaca + koordinat
#   .\phone.ps1 tap <label>            -> ketuk tengah widget berlabel itu
#   .\phone.ps1 tapxy <x> <y>          -> ketuk koordinat
#   .\phone.ps1 type <teks>            -> ketik teks
#   .\phone.ps1 login <user> <sandi>   -> isi form login lalu tekan MASUK
#   .\phone.ps1 log [jumlah]           -> logcat flutter
#   .\phone.ps1 shot <nama>            -> screenshot ke folder screenshots/
# adb sering menulis pesan biasa (jumlah file, "Success", dll) ke stderr.
# Kalau ErrorActionPreference=Stop, semua itu jadi error yang menghentikan
# skrip. Error preference diturunkan ke Continue supaya hanya script-nya
# sendiri yang perlu dicek.
$ErrorActionPreference = "Continue"
$adb = "C:\Users\user\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$pkg = "com.fruitpos.fruit_pos"
$shots = Join-Path $PSScriptRoot "screenshots"
New-Item -ItemType Directory -Force -Path $shots | Out-Null

function Get-Ui {
  & $adb shell uiautomator dump /sdcard/ui.xml | Out-Null
  $xml = & $adb shell cat /sdcard/ui.xml
  # Rangkum jadi satu baris per widget: label + bounds, biar enak dibaca.
  $nodes = [regex]::Matches($xml, '<node[^>]*>')
  $out = foreach ($n in $nodes) {
    $s = $n.Value
    $desc = [regex]::Match($s, 'content-desc="([^"]*)"').Groups[1].Value
    $txt = [regex]::Match($s, '\stext="([^"]*)"').Groups[1].Value
    $cls = [regex]::Match($s, 'class="([^"]*)"').Groups[1].Value
    $bnd = [regex]::Match($s, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    $pwd = [regex]::Match($s, 'password="true"').Success
    $label = if ($desc) { $desc } elseif ($txt) { $txt } else { $cls -replace 'android\.widget\.','' -replace 'android\.view\.','' }
    if (-not $bnd.Success) { continue }
    $x1 = [int]$bnd.Groups[1].Value; $y1 = [int]$bnd.Groups[2].Value
    $x2 = [int]$bnd.Groups[3].Value; $y2 = [int]$bnd.Groups[4].Value
    $tag = if ($pwd) { " [sandi]" } else { "" }
    [pscustomobject]@{
      Label  = $label
      Class  = $cls
      X      = [int](($x1 + $x2) / 2)
      Y      = [int](($y1 + $y2) / 2)
      Left   = $x1; Top = $y1; Right = $x2; Bottom = $y2
      Tag    = $tag
    }
  }
  # Buang wrapper kosong yang tidak informatif.
  $out | Where-Object { ($_.Label -and $_.Label -ne 'View') -or $_.Tag }
}

# Field input harus dicari dari class, bukan dari label: begitu berisi teks,
# label-nya berubah jadi isi teks dan tidak bisa dipakai untuk mengenali field.
function Get-Inputs {
  Get-Ui | Where-Object { $_.Class -eq 'android.widget.EditText' }
}

function Find-Label {
  param([string]$Needle)
  $ui = Get-Ui
  # Urutan ketelitian: persis > diawali > memuat. Tanpa ini, "Stok" akan
  # njempel ke kartu "Stok Menipis" di dashboard, bukan ke tab navigasi.
  $hit = $ui | Where-Object { $_.Label -eq $Needle }                 | Select-Object -First 1
  if (-not $hit) { $hit = $ui | Where-Object { $_.Label -like "$Needle*" }  | Select-Object -First 1 }
  if (-not $hit) { $hit = $ui | Where-Object { $_.Label -like "*$Needle*" } | Select-Object -First 1 }
  if (-not $hit) {
    # Ke stderr, bukan Write-Output: kalau lewat output stream, pesan
    # diagnosis ikut jadi bagian dari nilai balik fungsi dan pemanggil
    # ketuk koordinat kosong.
    [Console]::Error.WriteLine("  TIDAK KETEMU: '$Needle'")
    [Console]::Error.WriteLine("  Yang tersedia:")
    $ui | ForEach-Object { [Console]::Error.WriteLine("    - $($_.Label)$($_.Tag) @ $($_.X),$($_.Y)") }
    return $null
  }
  return $hit
}

$cmd = $args[0]
switch ($cmd) {
  "ui" {
    Get-Ui | ForEach-Object { Write-Output ("  {0,-42} @ {1},{2}{3}" -f $_.Label, $_.X, $_.Y, $_.Tag) }
  }
  "fields" {
    Get-Inputs | ForEach-Object { Write-Output ("  {0,-10} class={1} @ {2},{3}{4}" -f $_.Label, $_.Class, $_.X, $_.Y, $_.Tag) }
  }
  "tap" {
    $t = Find-Label $args[1]
    if ($t) {
      & $adb shell input tap $t.X $t.Y
      Write-Output "  ketuk '$($t.Label)' @ $($t.X),$($t.Y)"
      Start-Sleep -Milliseconds 700
    }
  }
  "tapxy" {
    & $adb shell input tap $args[1] $args[2]
    Write-Output "  ketuk $($args[1]),$($args[2])"
    Start-Sleep -Milliseconds 700
  }
  "type" {
    & $adb shell input text ($args[1] -replace ' ', '%s')
    Start-Sleep -Milliseconds 300
  }
  "swipe" {
    & $adb shell input swipe $args[1] $args[2] $args[3] $args[4] $args[5]
    Start-Sleep -Milliseconds 800
  }
  "back" {
    & $adb shell input keyevent 4
    Start-Sleep -Milliseconds 700
  }
  "login" {
    $user = $args[1]; $pass = $args[2]

    # Koordinat WAJIB diambil ulang sebelum tiap ketukan. Saat keyboard
    # terbuka, halaman ikut menggulir sehingga posisi field berubah; memakai
    # koordinat dari awal akan membuat teks ketik masuk ke field yang salah.
    function Fields {
      $f = Get-Inputs
      [pscustomobject]@{
        Plain  = $f | Where-Object { $_.Tag -ne ' [sandi]' } | Select-Object -First 1
        Secret = $f | Where-Object { $_.Tag -eq ' [sandi]' }     | Select-Object -First 1
      }
    }

    # Tunggu form benar-benar muncul: setelah "pm clear" + launch, app masih di
    # splash beberapa detik, jadi dump pertama sering masih kosong.
    $before = $null
    for ($tries = 0; $tries -lt 10; $tries++) {
      $before = Fields
      if ($before.Plain -and $before.Secret) { break }
      Start-Sleep -Seconds 2
    }
    if (-not $before.Plain -or -not $before.Secret) { Write-Output "  form login tidak ditemukan"; exit 1 }

    # Hanya bersihkan kalau isinya tidak kosong. Menghapus karakter lewat
    # keyevent pada field Flutter ternyata tidak andal (kursor kadang tetap di
    # tengah teks), jadi jalan paling aman adalah "pm clear" dari luar app.
    $isi = $before.Plain.Label
    if ($isi -and $isi -ne 'EditText') {
      Write-Output "  field username masih berisi '$isi', jalankan: phone.ps1 clear"
      exit 2
    }

    $f1 = Fields
    & $adb shell input tap $f1.Plain.X $f1.Plain.Y
    Start-Sleep -Milliseconds 500
    & $adb shell input text $user
    Start-Sleep -Milliseconds 500

    $f2 = Fields
    if ($f2.Secret) {
      & $adb shell input tap $f2.Secret.X $f2.Secret.Y
      Start-Sleep -Milliseconds 500
      & $adb shell input text $pass
      Start-Sleep -Milliseconds 500
    } else { Write-Output "  field sandi tidak ditemukan setelah keyboard terbuka" }

    $btn = Find-Label "MASUK"
    if ($btn) { & $adb shell input tap $btn.X $btn.Y; Write-Output "  login $user ditekan"; Start-Sleep -Seconds 5 }
  }
  "launch" {
    & $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 5
    Write-Output "  app dijalankan"
  }
  "restart" {
    & $adb shell am force-stop $pkg
    Start-Sleep -Seconds 1
    & $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 6
    Write-Output "  app direstart"
  }
  "clear" {
    & $adb shell pm clear $pkg
    Write-Output "  data app dihapus"
  }
  "log" {
    $n = if ($args[1]) { $args[1] } else { 40 }
    & $adb logcat -d -s flutter:* AndroidRuntime:E | Select-Object -Last $n
  }
  "logclear" { & $adb logcat -c; Write-Output "  logcat dibersihkan" }
  "shot" {
    $name = if ($args[1]) { $args[1] } else { "shot" }
    $out = Join-Path $shots "$name.png"
    & $adb shell screencap -p /sdcard/s.png
    & $adb pull /sdcard/s.png $out | Out-Null
    & $adb shell rm /sdcard/s.png
    Write-Output "  screenshot: $out"
  }
  "taplabel" {
    $t = Find-Label $args[1]
    if ($t) { Write-Output ("  {0} -> {1},{2}" -f $t.Label, $t.X, $t.Y) }
  }
  default {
    Write-Output "  perintah tidak dikenal: $cmd"
  }
}
