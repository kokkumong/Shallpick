# Shallpick

함께 찍은 사진을 고르고, 사진에 나온 사람의 의견을 확인한 뒤 공유를 준비하는 HCI 프로젝트입니다.

**Swift + SwiftUI로 iOS 앱을 만듭니다. 첫 목표는 다른 사람이 설치해서 핵심 흐름을 끝까지 실행할 수 있는 프로토타입 배포입니다.**

## 현재 상태

2026-11-16 기준 앱은 Shallpick 시작 화면이 있는 기본 Xcode 프로젝트입니다. 아래 정책은 앞으로 구현할 기준이며, 기능 구현이나 배포 완료를 뜻하지 않습니다.

| 항목 | 기준 |
| --- | --- |
| 앱 | Swift 6 / SwiftUI / iOS |
| 현재 최소 OS 설정 | iOS 26.0 — 실제 시연 기기와 맞는지 첫 빌드에서 확인 |
| 최소 배포 목표 | TestFlight 등 설치 가능한 빌드 + 핵심 흐름 + 시연 안내 |
| 허용하는 목업 | 소셜 로그인, 인물 추천, 로컬 데이터와 역할 전환 |
| 다음 단계 | 실제 다중 기기 동기화, 인증, 업로드, OS 공유 |
| Android | 현재 SwiftUI 구현 범위 밖. 필요하면 별도 계획으로 결정 |

## 먼저 읽기

1. [제품 정책](docs/PRODUCT_POLICY.md): 동의, 사진 수정, 요청 상태의 기준
2. [프로토타입 배포](docs/PROTOTYPE_DELIVERY.md): 최소 범위, 단계별 완료 조건, 설치 검증
3. [디자인 기준](docs/DESIGN_GUIDE.md): 최신 Figma와 화면 구성
4. [협업과 PR](CONTRIBUTING.md): 변경 요약, 규칙 적용, 실제 화면, 검증 결과

AI 작업자는 [AGENTS.md](AGENTS.md)를 먼저 따릅니다. [결정 기록](docs/DECISIONS.md)에는 이전 Expo 프로젝트에서 가져온 정책과 현재 선택을 구분했습니다.

## 실행과 확인

Mac에서 `Shallpick.xcodeproj`를 열고, 설치된 iOS SDK와 실행 기기를 확인한 뒤 `Shallpick`을 실행합니다. 실기기 배포에는 자신의 서명 계정 설정이 필요합니다. 저장소의 `DEVELOPMENT_TEAM`은 비어 있습니다.

```sh
xcodebuild -list -project Shallpick.xcodeproj
xcodebuild -project Shallpick.xcodeproj -scheme Shallpick \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

위 명령은 Mac에서 확인할 빌드 절차입니다. 실행 결과가 없으면 성공했다고 기록하지 않습니다. 현재 자동 CI는 PR 형식과 보고서 도구를 검사하며, iOS 빌드나 실기기 검증을 대신하지 않습니다.

PR 도구만 확인할 때는 Node.js 24 이상에서 다음을 실행합니다. Node는 협업 도구에만 사용하며 앱 런타임은 Swift입니다.

```sh
node --test scripts/pr-report.test.mjs
```
