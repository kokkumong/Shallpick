import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { renderReport, evidenceURL, checkPR } from './pr-report.mjs';

const sha = 'a'.repeat(40);
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6Jr4AAAAASUVORK5CYII=', 'base64');
const context = { repository: 'kokkumong/Shallpick', commit: sha, readBlob: () => png };
const report = () => ({
  summary: '사진 수정 후 다시 확인할 수 있습니다.',
  changes: [{ before: '이전 승인이 남음', after: '수정한 사진 재확인' }],
  rules: [{ name: 'P04', evidence: '사진 버전 변경 시 재확인' }],
  uiChanged: false, visualNote: '상태 계산만 변경, 화면 변경 없음.', screenshots: [],
  checks: [{ name: '상태 테스트', status: 'passed', detail: '수정 전후 동의 무효화 확인' }],
  prototype: { status: 'not-deployed', note: '이번 변경은 아직 배포하지 않음.' },
  remaining: [], draft: false,
});
const shot = () => ({ title: '재확인', after: 'docs/pr-evidence/review/after.png', environment: '테스트 환경', sourceCommit: sha, note: '새 화면, 이전 화면 없음.' });

test('문서/비 UI PR은 이유와 검증 결과를 포함하고 이미지를 만들지 않는다', () => {
  const body = renderReport(report(), context);
  assert.match(body, /해당 없음 — 상태 계산/);
  assert.match(body, /✅ 통과/);
  assert.doesNotMatch(body, /<img/);
  assert.deepEqual(checkPR(body, false), []);
});

test('UI PR은 실제 커밋 이미지 링크와 280px 전후 비교를 만든다', () => {
  const data = { ...report(), uiChanged: true, screenshots: [{ ...shot(), before: 'docs/pr-evidence/review/before.png', beforeSourceCommit: 'b'.repeat(40) }] };
  const body = renderReport(data, context);
  assert.match(body, new RegExp(`blob/${sha}/docs/pr-evidence/review/after.png`));
  assert.equal((body.match(/width="280"/g) ?? []).length, 2);
  assert.deepEqual(checkPR(body, false), []);
});

test('신규 화면에는 이전 화면이 없는 이유를 표시한다', () => {
  const body = renderReport({ ...report(), uiChanged: true, screenshots: [shot()] }, context);
  assert.match(body, /신규 화면 — 이전 화면 없음/);
});

test('UI 캡처 누락은 준비된 PR로 표시할 수 없다', () => {
  assert.throws(() => renderReport({ ...report(), uiChanged: true }, context), /Draft/);
  const body = renderReport({ ...report(), uiChanged: true, draft: true, visualBlockedReason: 'Mac 실행 환경 없음' }, context);
  assert.deepEqual(checkPR(body, true), []);
  assert.ok(checkPR(body, false).length > 0);
});

test('외부 경로, 상위 이동, 백슬래시, 비 이미지 파일을 거부한다', () => {
  for (const path of ['C:/secret.png', '../secret.png', 'docs/pr-evidence/../../secret.png', 'docs/pr-evidence/a\\b.png', 'docs/pr-evidence/a.svg']) {
    assert.throws(() => evidenceURL(path, context));
  }
});

test('이미지 형식과 용량을 검사한다', () => {
  assert.throws(() => evidenceURL('docs/pr-evidence/a.png', { ...context, readBlob: () => Buffer.from('this is not a bitmap') }), /형식/);
  assert.throws(() => evidenceURL('docs/pr-evidence/a.jpg', context), /형식/);
  assert.throws(() => evidenceURL('docs/pr-evidence/a.png', { ...context, readBlob: () => Buffer.alloc(5 * 1024 * 1024 + 1) }), /5MB/);
});

test('커밋되지 않은 이미지를 성공으로 만들지 않는다', () => {
  assert.throws(() => renderReport({ ...report(), uiChanged: true, screenshots: [shot()] }, { ...context, readBlob: () => { throw new Error('missing committed image'); } }), /missing/);
});

test('코드 커밋과 전 화면 커밋을 기록하도록 한다', () => {
  assert.throws(() => renderReport({ ...report(), uiChanged: true, screenshots: [{ ...shot(), sourceCommit: 'main' }] }, context), /sourceCommit/);
  assert.throws(() => renderReport({ ...report(), uiChanged: true, screenshots: [{ ...shot(), before: 'docs/pr-evidence/a.png' }] }, context), /beforeSourceCommit/);
});

test('실패한 검증과 미실행을 구분하고 실패한 PR은 Draft로 남긴다', () => {
  const data = report();
  data.checks[0].status = 'failed';
  assert.throws(() => renderReport(data, context), /Draft/);
  data.draft = true;
  assert.match(renderReport(data, context), /❌ 실패/);
  data.checks[0].status = 'not-run';
  assert.match(renderReport(data, context), /⏸ 미실행/);
});

test('배포 표시는 설치 경로, 빌드, 설치 확인 근거를 요구한다', () => {
  const data = report();
  data.prototype.status = 'deployed';
  assert.throws(() => renderReport(data, context));
  Object.assign(data.prototype, { url: 'https://testflight.apple.com/join/example', build: '테스트 빌드', installationCheck: '테스트용 확인 기록' });
  assert.match(renderReport(data, context), /설치 확인: 테스트용 확인 기록/);
  data.prototype.url = 'https://user:password@example.com/';
  assert.throws(() => renderReport(data, context), /인증정보/);
});

test('표와 HTML을 깨뜨리는 문구를 이스케이프한다', () => {
  const data = report();
  data.rules[0].evidence = '<script> | line\nnext';
  const body = renderReport(data, context);
  assert.match(body, /&lt;script&gt; &#124; line<br>next/);
});

test('비어 있는 본문과 미작성 PR 템플릿은 검사를 통과하지 못한다', () => {
  assert.ok(checkPR('', false).length > 0);
  const template = readFileSync(new URL('../.github/pull_request_template.md', import.meta.url), 'utf8');
  assert.ok(checkPR(template, false).length > 0);
});

test('내용 없는 규칙 표를 작성된 근거로 취급하지 않는다', () => {
  const body = renderReport(report(), context).replace('| P04 | 사진 버전 변경 시 재확인 |', '|  |  |');
  assert.ok(checkPR(body, false).some(message => message.startsWith('적용한 규칙:')));
});

test('Windows 줄바꿈과 제목 뒤 공백을 허용한다', () => {
  const body = renderReport(report(), context).replace('## 검증\n', '## 검증  \n').replaceAll('\n', '\r\n');
  assert.deepEqual(checkPR(body, false), []);
});

test('다른 절의 이미지를 UI 증거로 계산하지 않는다', () => {
  const body = renderReport(report(), context).replace('ui-change: no', 'ui-change: yes') + '\n![not evidence](https://example.com/image.png)';
  assert.ok(checkPR(body, false).some(message => message.includes('실행 화면')));
});
