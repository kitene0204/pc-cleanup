# PC 용량 정리

클릭 한 번으로 윈도우 임시 파일·캐시를 안전하게 지우는 프로그램.

- 실행: `PC용량정리.exe` 더블클릭 → 관리자 권한 [예]
- 매주 자동: `src\RegisterWeekly.ps1` (매주 일요일 12:00, 작업 이름 `PC용량정리_매주`)
- 미리보기(안 지우고 계산만): `powershell -ExecutionPolicy Bypass -File src\CleanPC.ps1 -Preview`

## 지우는 것
윈도우 임시 파일(temp, %temp%), 스토어 캐시(wsreset), 윈도우 업데이트 찌꺼기, 전송 최적화 캐시,
오류 보고서, 오래된 로그, 브라우저 캐시(크롬·엣지·웨일, 꺼져 있을 때만), 썸네일 캐시,
캡컷·프리미어 캐시, NVIDIA 설치 찌꺼기, uv·pip·npm 캐시.
물어보고 하는 것: 휴지통, DISM 구성요소 정리, 저장소 센스, 시작 프로그램 켜기·끄기.

## 절대 안 건드리는 것
사진·영상·문서·다운로드·바탕화면·음악·원드라이브·구글드라이브, OpenMontage, 시작 프로그램 실행 파일.
바로가기 폴더(정션)는 따라가지 않음.

## 파일
- `src/CleanPC.ps1` — 본체
- `src/launcher.ahk`, `src/icon.ico` — exe 만들기용 (Ahk2Exe, AutoHotkey v2)
- `src/RegisterWeekly.ps1` — 매주 자동 실행 등록

exe 다시 만들기:
```
"C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" /in src\launcher.ahk /out PC용량정리.exe /icon src\icon.ico /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```
