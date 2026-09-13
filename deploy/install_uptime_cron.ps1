# Install uptime monitor ZoBuah sebagai Windows Scheduled Task.
# Cron tiap 10 menit mengecek /health -- murni buatan sendiri (tanpa UptimeRobot).
#
# Cara pakai:  powershell -ExecutionPolicy Bypass -File deploy\install_uptime_cron.ps1
# Cara uninstall: schtasks /Delete /TN "ZoBuah-Uptime" /F

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot "health_check.py"
$python = (Get-Command python -ErrorAction Stop).Source

$taskName = "ZoBuah-Uptime"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $python -Argument "`"$script`"") -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

$task = Get-ScheduledTask -TaskName $taskName
Write-Host "OK: Task '$taskName' terdaftar, tiap 10 menit mengecek $script"
Write-Host "Status saat ini: $($task.State)"
Write-Host "Log hasil: di ~/.zobuah_uptime.log"

Start-ScheduledTask -TaskName $taskName
Write-Host "Task dijalankan sekali sekarang untuk verifikasi."