# PC 용량 정리 — 한 번 클릭으로 안전하게 임시 파일·캐시를 지웁니다.
# 사진·영상·문서·다운로드 폴더·구글 드라이브는 절대 건드리지 않습니다.
# 사용:  CleanPC.ps1            → 실제 정리 (관리자 권한으로 다시 실행됨)
#        CleanPC.ps1 -Preview   → 지우지 않고 "얼마나 지울 수 있는지"만 계산
param([switch]$Preview, [switch]$Auto)

$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'PC 용량 정리'

# ---------- 관리자 권한 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Preview) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ---------- 공통 도구 ----------
# 이름에 이 글자가 들어간 경로는 무조건 건너뜀 (안전장치)
$Excluded = @('\claude\', 'DriveFS', '\Google\Drive', 'OpenMontage')
# 이 폴더 안쪽은 무조건 건너뜀 (내 사진·영상·문서·다운로드·바탕화면·원드라이브)
$ExcludedRoots = @('Downloads', 'Pictures', 'Videos', 'Documents', 'Desktop', 'Music', 'OneDrive') |
    ForEach-Object { Join-Path $env:USERPROFILE $_ }

function Is-Excluded([string]$p) {
    foreach ($e in $Excluded) { if ($p -like "*$e*") { return $true } }
    foreach ($r in $ExcludedRoots) { if ($p -like "$r*") { return $true } }
    return $false
}

# ---------- 시작 프로그램 목록 (레지스트리 Run + 시작프로그램 폴더) ----------
# 끄기/켜기는 작업 관리자 "사용 안 함"과 똑같은 방식이라 언제든 되돌릴 수 있음
$ApprBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
function Get-RunEntries {
    $skip = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
    $srcs = @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Appr = "HKCU:\$ApprBase\Run" },
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Appr = "HKLM:\$ApprBase\Run" },
        @{ Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKLM:\$ApprBase\Run32" }
    )
    foreach ($s in $srcs) {
        $props = Get-ItemProperty -Path $s.Key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($skip -contains $p.Name) { continue }
            $cmd = [string]$p.Value
            $exe = $(if ($cmd -match '^\s*"([^"]+)"') { $Matches[1] } else { ($cmd -split '\s+')[0] })
            $appr = (Get-ItemProperty -Path $s.Appr -Name $p.Name -ErrorAction SilentlyContinue).($p.Name)
            [pscustomobject]@{ Name = $p.Name; Exe = [Environment]::ExpandEnvironmentVariables($exe)
                               Appr = $s.Appr; On = -not ($appr -and ($appr[0] % 2 -eq 1)) }
        }
    }
    $folders = @(
        @{ Dir = [Environment]::GetFolderPath('Startup');       Appr = "HKCU:\$ApprBase\StartupFolder" },
        @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Appr = "HKLM:\$ApprBase\StartupFolder" }
    )
    foreach ($f in $folders) {
        foreach ($l in (Get-ChildItem -LiteralPath $f.Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $appr = (Get-ItemProperty -Path $f.Appr -Name $l.Name -ErrorAction SilentlyContinue).($l.Name)
            [pscustomobject]@{ Name = $l.Name; Exe = $l.FullName; Appr = $f.Appr
                               On = -not ($appr -and ($appr[0] % 2 -eq 1)) }
        }
    }
}

function Set-StartupState($e, [bool]$on) {
    if (-not (Test-Path $e.Appr)) { New-Item -Path $e.Appr -Force | Out-Null }
    $bytes = New-Object byte[] 12
    if ($on) { $bytes[0] = 2 } else { $bytes[0] = 3; [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()).CopyTo($bytes, 4) }
    Set-ItemProperty -Path $e.Appr -Name $e.Name -Value $bytes -Type Binary
}

# 시작 프로그램이 임시 폴더 안에 있으면(예: ZoomIt) 지우지 않도록 보호
$Protected = @(Get-RunEntries | ForEach-Object { $_.Exe })

function Fmt([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f ($b / 1KB)
}

# 바로가기(정션·심볼릭 링크)는 따라가지 않고 파일만 모음 → 다른 폴더로 새어나가지 않음
function Get-SafeFiles([string]$root) {
    $start = Get-Item -LiteralPath $root -Force
    if (-not $start -or ($start.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push($start)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        foreach ($i in (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if (Is-Excluded $i.FullName) { continue }
            if ($Protected -contains $i.FullName) { continue }
            if ($i.PSIsContainer) { $stack.Push($i) } else { $i }
        }
    }
}

function Remove-EmptyDirs([string]$root) {
    Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not (Is-Excluded $_.FullName) } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
}

$Results = New-Object System.Collections.ArrayList

# $days: 이 날짜보다 오래된 파일만 지움 (지금 쓰고 있는 설치 파일 등을 보호)
function Clean-Folder([string]$name, [string[]]$paths, [int]$days = 1, [string]$pattern = '*') {
    $cut = (Get-Date).AddDays(-$days)
    $found = 0.0; $freed = 0.0; $fail = 0
    foreach ($p in $paths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        foreach ($f in (Get-SafeFiles $p)) {
            if ($f.Name -notlike $pattern) { continue }
            if ($f.LastWriteTime -gt $cut) { continue }
            $found += $f.Length
            if (-not $Preview) {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $f.Length }
                catch { $fail++ }
            }
        }
        if (-not $Preview) { Remove-EmptyDirs $p }
    }
    $amount = $(if ($Preview) { $found } else { $freed })
    [void]$Results.Add([pscustomobject]@{ 항목 = $name; 용량 = $amount })
    $note = $(if ($fail) { "  (사용 중이라 건너뛴 파일 $fail 개)" } else { '' })
    Write-Host ('  ✔ {0,-28} {1,10}{2}' -f $name, (Fmt $amount), $note) -ForegroundColor Green
}

function Ask([string]$q) {
    if ($Auto -or $Preview) { return $false }
    $a = Read-Host "$q (Y = 예 / 그냥 엔터 = 아니오)"
    return ($a -match '^[yYㅛ]')
}

function Free-C { (Get-PSDrive C).Free }

# ---------- 시작 ----------
Clear-Host
Write-Host ''
Write-Host '  ===========================================' -ForegroundColor Cyan
Write-Host '               PC 용량 정리' -ForegroundColor Cyan
Write-Host '  ===========================================' -ForegroundColor Cyan
if ($Preview) { Write-Host '  [미리보기] 아무것도 지우지 않고 계산만 합니다.' -ForegroundColor Yellow }
Write-Host '  사진·영상·문서·다운로드·구글드라이브는 건드리지 않아요.'
Write-Host ''
$before = Free-C
Write-Host ('  지금 C 드라이브 남은 공간: {0}' -f (Fmt $before))
Write-Host ''

# 브라우저가 켜져 있으면 그 브라우저 캐시는 건너뜀
$browsers = @(
    @{ Name = '크롬 캐시';   Proc = 'chrome';  Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ Name = '엣지 캐시';   Proc = 'msedge';  Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ Name = '웨일 캐시';   Proc = 'whale';   Root = "$env:LOCALAPPDATA\Naver\Naver Whale\User Data" }
)

Write-Host '  ▶ 정리 중...' -ForegroundColor Cyan

# 1) 영상 꿀팁 ① temp  (C:\Windows\Temp)
Clean-Folder '윈도우 임시 파일 (temp)' @("$env:windir\Temp")

# 2) 영상 꿀팁 ② %temp% (내 계정 임시 파일)
$userTemps = @($env:TEMP, "$env:LOCALAPPDATA\Temp") | Select-Object -Unique
Clean-Folder '내 임시 파일 (%temp%)' $userTemps

# 3) 영상 꿀팁 ③ wsreset (마이크로소프트 스토어 캐시)
if (-not $Preview) {
    $p = Start-Process wsreset.exe -WindowStyle Hidden -PassThru
    $null = $p | Wait-Process -Timeout 60
    Start-Sleep -Seconds 2
    Get-Process WinStore.App -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host '  ✔ 스토어 캐시 초기화 (wsreset)          완료' -ForegroundColor Green
} else {
    Write-Host '  · 스토어 캐시 초기화 (wsreset)          실제 정리 때 실행' -ForegroundColor DarkGray
}

# ----- 여기부터 추가 업그레이드 -----

# 4) 윈도우 업데이트 다운로드 찌꺼기 (설치 끝난 업데이트 파일)
if (-not $Preview) { Stop-Service wuauserv, bits -Force }
Clean-Folder '윈도우 업데이트 찌꺼기' @("$env:windir\SoftwareDistribution\Download") 3
if (-not $Preview) { Start-Service bits, wuauserv }

# 5) 전송 최적화 캐시 (업데이트를 다른 PC와 나누려고 쌓아둔 파일)
$doPath = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
$doSize = (Get-SafeFiles $doPath | Measure-Object Length -Sum).Sum
if (-not $Preview) { Delete-DeliveryOptimizationCache -Force *> $null }
[void]$Results.Add([pscustomobject]@{ 항목 = '전송 최적화 캐시'; 용량 = [double]$doSize })
Write-Host ('  ✔ {0,-28} {1,10}' -f '전송 최적화 캐시', (Fmt $doSize)) -ForegroundColor Green

# 6) 오류 보고서·충돌 기록
Clean-Folder '오류 보고서·충돌 기록' @(
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER",
    "$env:LOCALAPPDATA\CrashDumps") 0

# 7) 오래된 윈도우 기록 파일 (7일 지난 .log)
Clean-Folder '오래된 윈도우 기록(.log)' @("$env:windir\Logs\CBS", "$env:windir\Logs\DISM") 7 '*.log'

# 8) 인터넷 브라우저 캐시 (로그인·즐겨찾기·방문기록은 그대로)
foreach ($b in $browsers) {
    if (-not (Test-Path -LiteralPath $b.Root)) { continue }
    if (Get-Process $b.Proc -ErrorAction SilentlyContinue) {
        Write-Host ('  · {0,-28} 브라우저가 켜져 있어 건너뜀' -f $b.Name) -ForegroundColor DarkGray
        continue
    }
    $dirs = foreach ($prof in (Get-ChildItem -LiteralPath $b.Root -Directory -Force)) {
        foreach ($c in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { Join-Path $prof.FullName $c }
    }
    $dirs += Join-Path $b.Root 'ShaderCache'
    $dirs += Join-Path $b.Root 'GrShaderCache'
    Clean-Folder $b.Name $dirs 0
}

# 9) 사진 미리보기(썸네일) 캐시 — 탐색기가 다시 만들어 줌. 사진 자체는 그대로.
Clean-Folder '썸네일 미리보기 캐시' @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer") 0 'thumbcache_*.db'

# 10) 영상 편집 캐시 — 프로그램이 꺼져 있을 때만. 프로젝트·영상 파일은 그대로.
function Clean-App([string]$name, [string[]]$procs, [string[]]$paths, [int]$days) {
    foreach ($pr in $procs) {
        if (Get-Process $pr -ErrorAction SilentlyContinue) {
            Write-Host ('  · {0,-28} 프로그램이 켜져 있어 건너뜀' -f $name) -ForegroundColor DarkGray
            return
        }
    }
    Clean-Folder $name $paths $days
}
Clean-App '캡컷 캐시' @('CapCut') @("$env:LOCALAPPDATA\CapCut\User Data\Cache") 1
Clean-App '프리미어 미디어 캐시' @('Adobe Premiere Pro') @(
    "$env:APPDATA\Adobe\Common\Media Cache Files",
    "$env:APPDATA\Adobe\Common\Media Cache",
    "$env:APPDATA\Adobe\Common\Peak Files") 7

# 11) NVIDIA 드라이버 설치 찌꺼기
Clean-Folder 'NVIDIA 드라이버 설치 찌꺼기' @("$env:ProgramData\NVIDIA Corporation\Downloader") 1

# 12) 개발 도구 설치 캐시 (필요하면 자동으로 다시 받음)
$uvCache = "$env:LOCALAPPDATA\uv\cache"
$uvExe = Get-Command uv -ErrorAction SilentlyContinue
if ($uvExe -and (Test-Path -LiteralPath $uvCache)) {
    $b0 = [double](Get-SafeFiles $uvCache | Measure-Object Length -Sum).Sum
    $g = $b0
    if (-not $Preview) {
        & $uvExe.Source cache clean 2>&1 | Out-Null
        $g = $b0 - [double](Get-SafeFiles $uvCache | Measure-Object Length -Sum).Sum
        if ($g -lt 0) { $g = 0 }
    }
    [void]$Results.Add([pscustomobject]@{ 항목 = '파이썬 도구 캐시 (uv)'; 용량 = $g })
    Write-Host ('  ✔ {0,-28} {1,10}' -f '파이썬 도구 캐시 (uv)', (Fmt $g)) -ForegroundColor Green
}
Clean-Folder '파이썬 설치 캐시 (pip)' @("$env:LOCALAPPDATA\pip\cache") 0
Clean-Folder '노드 설치 캐시 (npm)' @("$env:LOCALAPPDATA\npm-cache\_cacache") 0

# ---------- 선택 항목 (물어보고 함) ----------
Write-Host ''
Write-Host '  ▶ 추가로 할까요? (아무것도 안 누르고 엔터 = 안 함)' -ForegroundColor Cyan

# 10) 휴지통
$rb = (New-Object -ComObject Shell.Application).Namespace(10)
$rbSize = 0.0; foreach ($it in $rb.Items()) { $rbSize += $it.Size }
if ($rbSize -gt 0) {
    Write-Host ('  휴지통에 {0} 이(가) 있어요. 비우면 되살릴 수 없어요.' -f (Fmt $rbSize))
    if (Ask '  휴지통을 비울까요?') {
        Clear-RecycleBin -Force
        [void]$Results.Add([pscustomobject]@{ 항목 = '휴지통'; 용량 = $rbSize })
        Write-Host ('  ✔ {0,-28} {1,10}' -f '휴지통', (Fmt $rbSize)) -ForegroundColor Green
    }
}

# 11) 윈도우 구성요소 정리 (DISM) — 안전하지만 5~15분 걸림
if (Ask '  윈도우 구성요소 깊은 정리를 할까요? (5~15분 걸림)') {
    Write-Host '  깊은 정리 중... 창을 닫지 마세요.' -ForegroundColor Yellow
    $d0 = Free-C
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart | Out-Null
    $gain = [double]((Free-C) - $d0); if ($gain -lt 0) { $gain = 0 }
    [void]$Results.Add([pscustomobject]@{ 항목 = '윈도우 구성요소 정리'; 용량 = $gain })
    Write-Host ('  ✔ {0,-28} {1,10}' -f '윈도우 구성요소 정리', (Fmt $gain)) -ForegroundColor Green
}

# 12) 저장소 센스 — 윈도우가 알아서 임시 파일을 계속 지워주는 기능
$ssKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
$ssOn = (Get-ItemProperty -Path $ssKey -Name '01').'01' -eq 1
if (-not $ssOn -and -not $Preview) {
    Write-Host '  "저장소 센스"를 켜면 윈도우가 한 달에 한 번 임시 파일을 알아서 지워요.'
    Write-Host '  (다운로드 폴더는 건드리지 않게 설정합니다)'
    if (Ask '  저장소 센스를 켤까요?') {
        if (-not (Test-Path $ssKey)) { New-Item -Path $ssKey -Force | Out-Null }
        Set-ItemProperty -Path $ssKey -Name '01'   -Value 1  -Type DWord   # 켜기
        Set-ItemProperty -Path $ssKey -Name '2048' -Value 30 -Type DWord   # 30일마다 실행
        Set-ItemProperty -Path $ssKey -Name '04'   -Value 1  -Type DWord   # 임시 파일 정리
        Set-ItemProperty -Path $ssKey -Name '512'  -Value 0  -Type DWord   # 다운로드 폴더: 절대 안 지움
        Set-ItemProperty -Path $ssKey -Name '256'  -Value 60 -Type DWord   # 휴지통: 60일 지난 것만
        Write-Host '  ✔ 저장소 센스 켜짐 (다운로드는 지우지 않음)' -ForegroundColor Green
    }
}

# ---------- 느려짐 점검 (알려만 주고 바꾸지 않음) ----------
Write-Host ''
Write-Host '  ▶ 컴퓨터 느려짐 점검 (알려만 드려요)' -ForegroundColor Cyan
# 디스크 건강 검사 — 이상하면 사진·영상 백업하라고 알려줌
$diskWarn = @()
Write-Host '  · 디스크 건강 검사'
foreach ($d in (Get-PhysicalDisk)) {
    $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    $bad = ($d.HealthStatus -ne 'Healthy') -or ($r.ReadErrorsUncorrected -gt 0) -or ($r.Wear -ge 90)
    $hours = $(if ($r.PowerOnHours) { '{0:N0}시간 사용' -f $r.PowerOnHours } else { '' })
    if ($bad) {
        $diskWarn += $d.FriendlyName
        Write-Host ("    ⚠ {0}  이상 신호! ({1}) 중요한 사진·영상을 다른 곳에 꼭 백업하세요." -f $d.FriendlyName, $d.HealthStatus) -ForegroundColor Red
    } else {
        Write-Host ("    ✔ {0}  건강함  {1}" -f $d.FriendlyName, $hours) -ForegroundColor Green
    }
}

# 시작 프로그램 켜고 끄기
$recommendOff = 'OneDriveSetup', 'Adobe Acrobat Synchronizer', 'Microsoft.Lists', 'GoogleDriveSync'
$mustKeep     = 'RtkAudUService', 'GoogleDriveFS', 'SecurityHealth', 'ALYac', 'AYAgent.aye'
$entries = @(Get-RunEntries)
Write-Host ''
Write-Host ('  · 컴퓨터 켤 때 같이 켜지는 프로그램: {0}개 (지금 켜짐 {1}개)' -f $entries.Count, @($entries | Where-Object On).Count)
$n = 0
foreach ($e in $entries) {
    $n++
    $state = $(if ($e.On) { '켜짐' } else { '꺼짐' })
    $tag = ''; $color = 'Gray'
    if ($recommendOff -contains $e.Name) { $tag = '  ← 꺼도 돼요'; if ($e.On) { $color = 'Yellow' } }
    elseif ($mustKeep -contains $e.Name) { $tag = '  ← 꼭 두세요' }
    if (-not $e.On) { $color = 'DarkGray' }
    Write-Host ('    [{0,2}] {1}  {2}{3}' -f $n, $state, $e.Name, $tag) -ForegroundColor $color
}
if (-not $Auto -and -not $Preview) {
    $ans = Read-Host '  켜고 끌 번호를 쉼표로 적어주세요 (예: 2,5 / 그냥 엔터 = 안 바꿈)'
    foreach ($k in ($ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' })) {
        $e = $entries[[int]$k - 1]
        if (-not $e) { continue }
        Set-StartupState $e (-not $e.On)
        Write-Host ('    ✔ {0} → {1}' -f $e.Name, $(if ($e.On) { '꺼짐 (다음 부팅부터)' } else { '켜짐' })) -ForegroundColor Green
    }
}
$up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
if ($up.TotalDays -ge 7) {
    Write-Host ('  · 컴퓨터를 {0}일째 껐다 켜지 않았어요. 가끔 "다시 시작"하면 빨라져요.' -f [int]$up.TotalDays) -ForegroundColor Yellow
}

# ---------- 결과 ----------
$total = ($Results | Measure-Object 용량 -Sum).Sum
$after = Free-C
Write-Host ''
Write-Host '  ===========================================' -ForegroundColor Cyan
if ($Preview) {
    Write-Host ('   지울 수 있는 용량: 약 {0}' -f (Fmt $total)) -ForegroundColor Cyan
} else {
    Write-Host ('   정리한 용량: 약 {0}' -f (Fmt $total)) -ForegroundColor Cyan
    Write-Host ('   C 드라이브 남은 공간: {0}  →  {1}' -f (Fmt $before), (Fmt $after)) -ForegroundColor Cyan
}
Write-Host '  ===========================================' -ForegroundColor Cyan
Write-Host ''

# 기록 남기기
$logDir = Join-Path $PSScriptRoot '정리기록'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$line = "$stamp  $(if($Preview){'미리보기'}else{'정리'})  합계 $(Fmt $total)  /  " + (($Results | ForEach-Object { "$($_.항목) $(Fmt $_.용량)" }) -join ', ')
Add-Content -LiteralPath (Join-Path $logDir '기록.txt') -Value $line -Encoding UTF8

# 자동 실행일 때는 화면 오른쪽 아래 알림으로 결과를 알려줌
function Show-Toast([string]$title, [string]$body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $t = $xml.GetElementsByTagName('text')
        [void]$t.Item(0).AppendChild($xml.CreateTextNode($title))
        [void]$t.Item(1).AppendChild($xml.CreateTextNode($body))
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {}
}
if ($Auto -and -not $Preview) {
    Show-Toast '🧹 PC 용량 정리 완료' ('이번에 {0} 정리했어요. C 드라이브 남은 공간 {1}' -f (Fmt $total), (Fmt $after))
    if ($diskWarn.Count) {
        Show-Toast '⚠ 디스크 이상 신호' ("{0} — 중요한 사진·영상을 백업하세요" -f ($diskWarn -join ', '))
    }
}

if (-not $Auto) { Read-Host '  끝! 엔터를 누르면 창이 닫혀요' | Out-Null }
