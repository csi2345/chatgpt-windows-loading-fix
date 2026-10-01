# ChatGPT Windows Loading Fix

Microsoft Store의 일반 **ChatGPT Windows 앱**이 GPT 로고 화면에서 계속 멈추는 문제를 우회하는 비공식 PowerShell 실행기입니다.

> [!IMPORTANT]
> 이 프로젝트는 OpenAI의 공식 도구가 아닙니다. 앱 파일이나 사용자 데이터를 수정하지 않는 임시 우회책이며, 향후 ChatGPT 업데이트로 내부 구조가 바뀌면 작동하지 않을 수 있습니다.

## 적용 대상

- Microsoft Store의 일반 **ChatGPT 앱**
- 패키지 이름: `OpenAI.Codex`
- 증상: 앱 실행 후 중앙의 GPT 로고에서 더 진행되지 않음

다음 앱은 대상이 아닙니다.

- ChatGPT Beta (`OpenAI.CodexBeta`)
- ChatGPT Classic
- 웹 브라우저의 ChatGPT

## 지원 환경

- 최신 업데이트가 설치된 Windows 10 또는 Windows 11
- Microsoft Store에서 설치한 일반 ChatGPT 앱
- Windows PowerShell 5.1 (`powershell.exe`)
- 관리자 권한은 필요하지 않습니다.

확인된 환경:

- Windows 10 22H2 빌드 19045 / ChatGPT `26.928.3736.0`
- Windows 11 / Microsoft Store ChatGPT 앱

Windows 10에서는 Store 패키지의 `ChatGPT.exe`를 파일 경로로 직접 실행하면 `Access is denied`가 발생할 수 있습니다. 이 실행기는 Windows의 패키지 활성화 API를 사용하므로 `ChatGPT.exe`를 직접 실행하지 않습니다.

> [!WARNING]
> 실행기는 현재 실행 중인 **일반 ChatGPT 앱**을 먼저 종료합니다. 작성 중인 메시지가 있다면 실행 전에 복사해 두세요. Beta와 Classic은 종료하지 않습니다.

## 실행 방법

1. [`Start-ChatGPT-Fixed.ps1`](./Start-ChatGPT-Fixed.ps1)을 다운로드합니다.
2. 파일이 있는 폴더에서 PowerShell 또는 터미널을 엽니다.
3. 다음 명령을 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Start-ChatGPT-Fixed.ps1"
```

파일을 다른 폴더에 저장했다면 전체 경로를 사용할 수 있습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\Start-ChatGPT-Fixed.ps1"
```

스크립트 내부의 경로는 수정하지 않아도 됩니다. 설치된 `OpenAI.Codex` 패키지와 실제 `ChatGPT.exe` 위치를 자동으로 찾습니다.

앱이 정상 화면으로 전환되기까지 약 15~30초가 걸릴 수 있습니다.

## 선택 사항: 바로가기 만들기

바탕 화면에서 마우스 오른쪽 버튼을 누르고 **새로 만들기 → 바로 가기**를 선택한 다음, 항목 위치에 다음 내용을 입력합니다. 아래의 스크립트 경로만 실제 저장 위치에 맞게 바꾸면 됩니다.

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Tools\Start-ChatGPT-Fixed.ps1"
```

바로가기 이름은 예를 들어 `ChatGPT (정상 실행)`으로 지정할 수 있습니다.

## 다운로드한 스크립트가 차단될 때

인터넷에서 받은 파일이라는 이유로 Windows가 실행을 차단하면 다음 명령을 한 번 실행합니다.

```powershell
Unblock-File -LiteralPath ".\Start-ChatGPT-Fixed.ps1"
```

회사 PC에서 PowerShell, AppLocker 또는 로컬 디버깅 기능이 정책으로 차단된 경우에는 시스템 관리자 권한이 필요할 수 있습니다.

## 작동 방식

실행기는 다음 작업만 수행합니다.

1. 설치된 일반 ChatGPT Store 패키지를 자동으로 찾습니다.
2. 일반 ChatGPT 프로세스만 종료하고 등록된 Store 패키지 ID로 공식 `ChatGPT.exe`를 다시 활성화합니다.
3. 앱의 Chromium 디버깅 인터페이스를 `127.0.0.1`의 임의 포트에 엽니다.
4. 빈 기본 라우트 대신 유효한 초기 라우트로 렌더러를 준비합니다.
5. 앱 자체의 내부 탐색 메시지를 사용해 ChatGPT 홈 화면으로 이동합니다.

ChatGPT 패키지 파일, 계정 정보, 대화 기록 또는 앱 프로필은 변경하거나 삭제하지 않습니다.

## 보안 참고 사항

우회 처리를 위해 ChatGPT가 실행되는 동안 Chromium 원격 디버깅 포트가 로컬 루프백 주소 `127.0.0.1`에 열립니다.

- 외부 네트워크에는 바인딩하지 않습니다.
- 포트 번호는 실행할 때마다 임의로 선택합니다.
- ChatGPT를 완전히 종료하면 해당 포트도 닫힙니다.
- 같은 PC의 다른 프로세스는 로컬 디버깅 포트에 접근할 수 있으므로, 신뢰할 수 없는 프로그램이 실행 중인 환경에서는 사용하지 마세요.

## 문제 해결

### `OpenAI.Codex` 패키지를 찾을 수 없다는 메시지

Microsoft Store의 일반 ChatGPT 앱이 설치되어 있는지 확인하세요. Beta 또는 Classic만 설치된 경우 이 실행기는 작동하지 않습니다.

### `Access is denied` 또는 `액세스가 거부되었습니다` 메시지

초기 버전의 실행기는 설치 폴더에 있는 `ChatGPT.exe`를 직접 실행했기 때문에 일부 Windows 10 환경에서 이 오류가 발생했습니다. 최신 `Start-ChatGPT-Fixed.ps1`을 다시 다운로드해 실행하세요. 최신 버전은 등록된 Store 패키지 ID로 앱을 활성화합니다.

### 여전히 로고 화면에 멈춤

1. 작업 관리자에서 일반 ChatGPT가 완전히 종료됐는지 확인합니다.
2. 스크립트를 다시 실행하고 최대 30초 기다립니다.
3. VPN, 보안 프로그램 또는 회사 정책이 `127.0.0.1` 연결을 차단하는지 확인합니다.

### 업데이트 후 작동하지 않음

이 실행기는 특정 라우팅 오류를 대상으로 합니다. OpenAI가 오류를 수정했거나 앱 내부 라우팅 구조를 변경했다면 일반 ChatGPT 아이콘으로 실행해 보고, 더 이상 필요하지 않으면 이 스크립트를 삭제하세요.

## 제거

별도의 설치 작업은 없습니다. 다운로드한 `Start-ChatGPT-Fixed.ps1`과 직접 만든 바로가기만 삭제하면 됩니다.

## Disclaimer

This is an unofficial, temporary workaround for the Microsoft Store ChatGPT app being stuck on its loading logo. It is not affiliated with or endorsed by OpenAI.
