# 결정 기록

## 2026-11-16 — Shallpick 정책 이관과 Swift 선택

- 사용자가 Shallpick으로 기존 정책을 옮겨 개선·푸시하도록 요청했고, 이어서 **Swift로 진행**하기로 확인했습니다.
- 현재 저장소의 SwiftUI/Xcode 구조를 유지합니다. 이전 Expo 앱 코드, 의존성, 빌드 명령은 옮기지 않습니다.
- 최소 목표는 설치 가능한 iOS 프로토타입입니다. 소셜 로그인과 인물 추천 등은 명시적인 목업을 허용합니다. 실제 다중 기기 동기화와 Android는 이 최소 목표와 구분합니다.
- PR마다 변경 요약, 적용 규칙, 실제 화면, 검증 결과, 배포 상태를 AI가 정리하도록 템플릿·보고서 도구·자동 검사를 추가합니다.
- 공감과 동의 구분, 요청·사진·게시 맥락 버전, 수정본 재확인, 원본 보존, 실제 연결 여부의 정직한 표시는 계속 유지합니다.

### 가져온 근거

이전 저장소: [swaan-kim/hci-photos](https://github.com/swaan-kim/hci-photos/tree/cd2ecd29a881084f41d270c9138edd2f77b2377e)

해당 기준판의 `AGENTS.md`, `CONTRIBUTING.md`, `docs/CONVENTIONS.md`, `docs/DECISIONS.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN_HANDOFF.md`, `docs/V7_PEOPLE_UI.md`와 PR 템플릿을 참고했습니다. 최신 V7의 인물 확인, 요청 배지, 그레이스케일 정책을 우선했습니다.

이전 앱의 테스트·화면 검수 결과는 Shallpick의 검증 결과로 옮기지 않았습니다. 기존 보고서, 원본 FigJam/Overleaf, 개인 사진과 인증정보도 이관 대상이 아닙니다.

### 이후에 결정할 것

- 배포 담당, Mac/Xcode 환경, 설치할 iPhone과 OS
- 사용 가능한 TestFlight 또는 다른 실제 설치 경로
- 수업 제출에 실제 다중 기기 동기화가 필수인지
- 첫 구현의 저장 방식, 테스트 타깃, 공용 UI와 화면 상태 구조

구현 PR에서 근거와 선택 이유를 짧게 갱신합니다. 논의 중인 대안을 확정 결정으로 바꾸지 않습니다.
