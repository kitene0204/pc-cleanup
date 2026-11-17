# 매주 일요일 낮 12시에 PC 용량 정리를 조용히 자동 실행하도록 등록
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$ps = Join-Path $PSScriptRoot 'CleanPC.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps`" -Auto"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 12:00
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)
try {
    Register-ScheduledTask -TaskName 'PC용량정리_매주' -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description '매주 임시 파일·캐시 자동 정리 (휴지통·깊은 정리는 안 함)' -Force -ErrorAction Stop | Out-Null
    Write-Host ''
    Write-Host '  ✔ 등록 완료! 매주 일요일 낮 12시에 자동으로 정리해요.' -ForegroundColor Green
    Write-Host '    (그 시간에 컴퓨터가 꺼져 있으면 다음에 켰을 때 해요)'
} catch {
    Write-Host "  ✖ 등록하지 못했어요: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Read-Host '  엔터를 누르면 창이 닫혀요' | Out-Null
