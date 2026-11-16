# 협업과 PR

작업 목표는 사용자가 실행할 수 있는 작은 흐름을 완성하고, 검토자가 변화와 근거를 빠르게 확인하게 하는 것입니다.

## 작업 단위

- 최신 `main`에서 `feat/<작업명>`, `fix/<작업명>`, `docs/<작업명>` 브랜치를 만듭니다.
- 시작할 때 사용자 상황, 바뀔 동작, 완료 기준, 관련 Figma 프레임을 짧게 정합니다. 큰 작업은 화면 단위보다 끝까지 실행되는 흐름으로 나눕니다.
- 커밋은 `feat:`, `fix:`, `docs:`, `test:`, `chore:`처럼 목적이 드러나게 씁니다.
- PR 하나에는 관련 변경만 넣습니다. 무관한 정리, 의존성 추가, 프로젝트 전환을 함께 넣지 않습니다.

## 모든 PR의 읽는 순서

| 순서 | 작성할 내용 |
| --- | --- |
| 변경 요약 | 어떤 상황에서 무엇이 달라지는지 1~3문장 |
| 적용한 규칙 | 이번 변경에 관계된 정책 2~4개와 적용 근거. 해당 없으면 이유 |
| 화면 확인 | UI 변경은 전후 캡처를 나란히, 문서 변경은 해당 없음과 이유 |
| 검증 | 실행한 명령/과업, 통과·실패·미실행, 기기/OS와 제한 |
| 프로토타입 | 미배포 또는 설치 경로·빌드 번호·설치 확인 결과 |
| 남은 작업 | 아직 목업인 동작, 막힌 항목, 후속 작업 |

과정 설명보다 바뀐 결과를 먼저 씁니다. 규칙을 지켰다는 체크 표시만 나열하지 말고, “사진 버전이 바뀌면 해당 사진을 재확인 상태로 전환”처럼 근거를 적습니다.

## 화면 첨부

- 실제 기기나 시뮬레이터에서 실행한 화면을 씁니다. 디자인 시안은 별도로 표시하고 구현 캡처를 대체하지 않습니다.
- 대표 흐름 1~3개를 골라 **변경 전 / 변경 후**를 280px 너비로 나란히 보여줍니다. 전체 해상도 이미지는 클릭해서 볼 수 있게 둡니다. 긴 추가 자료는 접기 영역에 넣습니다.
- 같은 기기·상태·데이터로 비교하고, 기기명, OS, 화면 크기, 캡처한 코드 커밋을 기록합니다. 새로운 화면에는 이전 화면 없음이라고 적습니다.
- 작은 화면도 확인합니다. 원래 디자인의 390/360px은 참고 폭이며, SwiftUI 검증에는 실제 시뮬레이터 이름과 포인트 크기를 적습니다.
- `docs/pr-evidence/<작업명>/`에 PNG/JPEG를 커밋합니다. 개인정보와 실제 단체 사진을 노출하지 않습니다. 한 이미지 최대 5MB, 글자가 읽히는 크기를 유지합니다.
- 캡처할 수 없는 UI 변경은 사유를 적고 Draft로 유지합니다. 리뷰 준비 상태로 바꾸기 전에 실제 화면을 추가합니다.

Mac에서 화면을 확인한 뒤 캡처하는 예:

```sh
mkdir -p docs/pr-evidence/photo-review
xcrun simctl io booted screenshot docs/pr-evidence/photo-review/after.png
```

자동 보고서 도구는 **이미 커밋한 이미지 파일의 존재와 형식**을 검사하고 고정 커밋 URL을 만듭니다. 실제 실행 화면인지, 글자가 읽히는지, 개인정보가 없는지는 작성자와 리뷰어가 확인합니다.

## AI 보고서 만들기

Node.js 24 이상이 필요합니다. 앱에 Node 패키지를 추가하지 않습니다.

1. `.github/pr-report.example.json`을 `.local/pr-report.json`으로 복사하고 실제 결과로 채웁니다. 예제의 통과 결과를 그대로 쓰지 않습니다.
2. UI 변경은 `uiChanged: true`와 `screenshots`를 채웁니다. 이미지 항목은 다음 형태입니다.

```json
{
  "title": "사진별 응답",
  "before": "docs/pr-evidence/photo-review/before.png",
  "after": "docs/pr-evidence/photo-review/after.png",
  "environment": "실제 사용한 시뮬레이터 / OS / 포인트 크기",
  "sourceCommit": "화면을 실행한 코드의 40자리 커밋",
  "beforeSourceCommit": "이전 화면을 실행한 코드의 40자리 커밋",
  "note": "사진을 제외한 후에도 앨범 원본이 유지되는 화면"
}
```

새 화면이면 `before`와 `beforeSourceCommit`을 생략하고 `note`에 이유를 적습니다. 전 화면이 있으면 `beforeSourceCommit`도 기록합니다. 이미지 파일은 현재 커밋에 함께 넣으므로 링크가 브랜치 이동에 따라 바뀌지 않습니다. 캡처 후 앱 코드가 달라졌다면 다시 실행·캡처합니다.

3. 코드와 캡처를 커밋·푸시한 뒤 본문을 생성합니다.

```sh
node scripts/pr-report.mjs .local/pr-report.json .local/pr-body.md
gh pr create --base main --title "feat: 사진별 응답 흐름 추가" --body-file .local/pr-body.md
# 기존 PR은 새로 만들지 않고 갱신
gh pr edit <PR번호> --body-file .local/pr-body.md
```

도구는 PR을 직접 게시하지 않습니다. AI가 생성된 본문을 읽고 사용자에게 허용된 범위에서 생성/갱신합니다. `draft: true`인 보고서나 미해결 실패는 `gh pr create --draft`로 올립니다. 보고서의 Draft 표시는 GitHub PR 상태를 자동 변경하지 않습니다.

## 검증과 병합

- 도메인 변경: 관련 Swift 동작 테스트. 테스트 타깃이 없으면 첫 정책 구현 PR에서 추가합니다.
- 앱 변경: Mac에서 Xcode 빌드, 주요 흐름 실행, UI 변경 시 화면 확인. 실행 명령과 환경을 PR에 적습니다.
- 협업 도구 변경: `node --test scripts/pr-report.test.mjs`.
- 문서만 변경: 링크·현재 코드와의 일치·`git diff --check`. 관련 없는 앱 테스트를 새로 만들지 않습니다.
- `PR quality` CI는 보고서 형식과 도구 테스트입니다. **iOS 빌드 통과나 배포 성공 표시가 아닙니다.** 실패한 검사와 빠진 구현 검증은 해결 후 리뷰 준비로 전환합니다.
- 팀원 1명 리뷰와 관련 검사 통과 후 squash merge를 기본으로 합니다. AI는 명시적인 병합 요청 없이 병합하지 않습니다. 브랜치 보호는 저장소 관리자가 별도로 설정해야 하며 문서만으로 강제되지 않습니다.

PR 본문 자동 검사에는 `pull_request`의 `edited` 이벤트도 사용하므로 본문 보완 후 다시 검사됩니다. `.github/pull_request_template.md`는 기본 브랜치에 병합된 뒤 새 PR에 자동 적용됩니다. [GitHub PR 템플릿 안내](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository)
