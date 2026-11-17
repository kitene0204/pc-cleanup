#Requires AutoHotkey v2.0
;@Ahk2Exe-SetDescription PC 용량 정리
ps := A_ScriptDir "\src\CleanPC.ps1"
if !FileExist(ps) {
    MsgBox "src\CleanPC.ps1 파일을 찾을 수 없어요.`n이 프로그램은 PC용량정리 폴더 안에서 실행해 주세요.", "PC 용량 정리"
    ExitApp
}
try Run '*RunAs powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps '"'