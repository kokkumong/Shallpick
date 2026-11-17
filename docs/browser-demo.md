# Windows에서 Shallpick 시연하기

SwiftUI 앱을 GitHub의 macOS 실행기에서 빌드하고, Appetize의 iPhone 시뮬레이터를 Windows 브라우저에서 조작합니다. 웹으로 다시 만든 화면이 아니라 이 저장소의 iOS 앱입니다.

## 3분 시연 순서

1. Appetize에서 iOS 26 이상인 iPhone을 선택하고 실행합니다.
2. **로그인 없이 둘러보기** → **주말 나들이**를 누릅니다.
3. 아래 수달 버튼을 눌러 사진 두 장을 고른 뒤 오른쪽 위 **다음**을 누릅니다.
4. 질문을 입력하고 **보내기**를 누릅니다. 뒤로 갔다가 채팅에 다시 들어오면 내용이 유지됩니다.
5. 홈의 종 버튼으로 **샘플 질문**을 띄우고 **바로 응답하기**를 눌러 이동합니다.
6. 홈의 **다시 시작**으로 샘플 상태를 초기화하거나 **종료**로 로그인 화면에 돌아갑니다.

추가로 확인할 수 있는 것: 폴더 검색, Grid/List 전환, 새 폴더 만들기, 초대 코드 `DEMO26`으로 참여, 사진 추가 화면에서 샘플 사진 3장 추가, 질문 첨부 취소, 첨부 사진 크게 보기.

## 시연 범위

| 동작 | 이 빌드에서의 동작 |
| --- | --- |
| 로그인 | 별도 계정 없이 샘플 사용자로 시작 |
| 사진과 대화 | 번들 사진과 메모리 데이터. 종료·초기화하면 리셋 |
| 사진 추가 | 실제 갤러리 대신 샘플 사진 3장 추가 |
| 초대 | 같은 시연 세션 안에서 코드로 폴더 참여 |
| QR | 카메라 대신 샘플 초대 코드를 채워 입력 과정 시연 |
| 알림 | 홈 종 버튼으로 명시적인 샘플 질문 발생 |
| 여러 사람의 실시간 참여, 카카오 로그인, 실제 업로드, APNs | 시연 빌드의 검증 범위에 포함하지 않음 |

`SHALLPICK_DEMO` 빌드 조건이 있을 때만 시연 진입이 나타납니다. 이 조건에서는 Supabase 클라이언트 생성과 Kakao SDK 초기화를 차단합니다. 인증정보를 넣어도 실서버에 연결하지 않습니다. 일반 빌드는 기존 로그인 경로를 사용합니다.

## 최신 앱을 다시 만들 때

1. `iOS browser demo` Actions 실행이 성공했는지 확인합니다. 앱 빌드와 UI 테스트는 각각 확인해야 합니다.
2. 실행 페이지의 `Shallpick-Appetize-<commit>` artifact를 내려받아 **한 번 압축 해제**합니다.
3. 그 안의 **Shallpick-Appetize.zip**을 Appetize에 업로드합니다. artifact 바깥 ZIP이나 `.ipa`를 올리지 않습니다.
4. `BUILD.txt`의 커밋을 PR과 대조합니다. `SHA256.txt`는 업로드용 ZIP 해시입니다.
5. Appetize에서 iOS 26 이상으로 실행하고 위 시연 순서를 확인합니다.

Actions 산출물은 14일 보관됩니다. 필요하면 내려받아 보관합니다. `main` 반영 후에는 Actions의 **Run workflow**로도 생성할 수 있습니다. 현재 브랜치에서는 push/PR 실행을 사용합니다.

## 빌드와 검증

- 표준 GitHub `macos-15` 실행기에서 Xcode 26.3을 선택하며 로그에 버전을 남깁니다. 일반 빌드와 시연 빌드는 같은 작업 폴더를 순서대로 사용해 공통 라이브러리 빌드를 재사용합니다.
- 일반 앱과 시연 앱을 각각 컴파일합니다. 배포 인증서와 Apple Developer 유료 계정은 이 시뮬레이터 빌드에 필요하지 않습니다.
- `scripts/configure-ui-tests.rb`가 CI 작업 공간에만 UI 테스트 타깃을 만듭니다. 팀의 Xcode 프로젝트 파일을 덮어쓴 결과는 커밋하지 않습니다.
- `UITests/DemoFlowTests.swift`가 사진 선택, 질문 전송, 재진입 후 유지, 초기화, 샘플 사진 추가, 알림 이동, 종료를 확인합니다.
- `iOS-demo-verification-<commit>`에 로그, XCTest 결과와 실제 시뮬레이터 스크린샷을 남깁니다. 빌드 ZIP이 있어도 테스트 실패 시 검증 완료로 표시하지 않습니다.
- Appetize 계정/API 토큰은 저장소에 넣지 않습니다. 최초 연결은 계정 소유자가 로그인한 브라우저에서 업로드합니다. 자동 업로드는 별도 API 자격증명을 연결한 이후에 추가할 수 있습니다.

출처: [Appetize iOS 업로드 규격](https://docs.appetize.io/platform/app-management/uploading-apps/ios), [GitHub macOS 실행기 구성](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md). Appetize 요금제별 실행 시간은 계정 화면에서 확인합니다.
