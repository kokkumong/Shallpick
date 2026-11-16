// Node standard library only. This tool formats evidence; it never invents or publishes it.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sections = ['변경 요약', '적용한 규칙', '화면 확인', '검증', '프로토타입', '남은 작업'];
const statusLabels = { passed: '✅ 통과', failed: '❌ 실패', 'not-run': '⏸ 미실행' };
const shaPattern = /^[a-f0-9]{40}$/;

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function requiredText(value, name) {
  requireValue(typeof value === 'string' && value.trim().length > 0, `${name}: 내용이 필요합니다.`);
  return value.trim();
}

function rows(value, name, minimum = 1) {
  requireValue(Array.isArray(value) && value.length >= minimum, `${name}: 최소 ${minimum}개 항목이 필요합니다.`);
  return value;
}

function html(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function cell(value) {
  return html(value).replaceAll('|', '&#124;').replaceAll('\r', '').replaceAll('\n', '<br>');
}

function httpsURL(value, name) {
  const url = new URL(requiredText(value, name));
  requireValue(url.protocol === 'https:' && !url.username && !url.password, `${name}: 인증정보 없는 HTTPS URL을 사용하세요.`);
  return url.href;
}

export function evidenceURL(path, { repository, commit, readBlob }) {
  requireValue(typeof path === 'string' && /^docs\/pr-evidence\/.+\.(png|jpe?g)$/i.test(path), '캡처는 docs/pr-evidence/의 PNG/JPEG여야 합니다.');
  requireValue(!path.includes('\\') && !path.includes(':') && !path.split('/').some(p => !p || p === '.' || p === '..'), '캡처 경로에 상대 이동이나 외부 경로를 사용할 수 없습니다.');
  requireValue(shaPattern.test(commit), '이미지 링크에는 40자리 커밋이 필요합니다.');
  requireValue(/^[\w.-]+\/[\w.-]+$/.test(repository), '올바른 GitHub 저장소 이름이 필요합니다.');
  const bytes = readBlob(path);
  requireValue(Buffer.isBuffer(bytes) && bytes.length > 8 && bytes.length <= 5 * 1024 * 1024, '캡처는 5MB 이하 이미지여야 합니다.');
  const png = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  requireValue(/\.png$/i.test(path) ? png : jpeg, '확장자와 이미지 형식이 일치하지 않습니다.');
  return `https://github.com/${repository}/blob/${commit}/${path.split('/').map(encodeURIComponent).join('/')}?raw=true`;
}

export function renderReport(data, context) {
  const summary = requiredText(data.summary, 'summary');
  requireValue(typeof data.uiChanged === 'boolean', 'uiChanged는 true 또는 false여야 합니다.');
  requireValue(typeof data.draft === 'boolean', 'draft는 true 또는 false여야 합니다.');
  const shots = rows(data.screenshots, 'screenshots', 0);
  requireValue(data.uiChanged || shots.length === 0, 'UI 변경이 없으면 구현 화면을 첨부하지 마세요.');
  const blocked = data.uiChanged && shots.length === 0;
  if (blocked) {
    requireValue(data.draft, '캡처가 없는 UI 변경은 Draft로 작성하세요.');
    requiredText(data.visualBlockedReason, 'visualBlockedReason');
  }
  const changes = rows(data.changes, 'changes').map(row => `| ${cell(requiredText(row.before, 'before'))} | ${cell(requiredText(row.after, 'after'))} |`);
  const rules = rows(data.rules, 'rules').map(row => `| ${cell(requiredText(row.name, 'rule.name'))} | ${cell(requiredText(row.evidence, 'rule.evidence'))} |`);
  const checks = rows(data.checks, 'checks').map(row => {
    requireValue(Object.hasOwn(statusLabels, row.status), '검증 결과는 passed / failed / not-run 중 하나여야 합니다.');
    requireValue(row.status !== 'failed' || data.draft, '실패한 검증이 있으면 Draft로 작성하세요.');
    return `| ${cell(requiredText(row.name, 'check.name'))} | ${statusLabels[row.status]} | ${cell(requiredText(row.detail, 'check.detail'))} |`;
  });
  const visual = [];
  if (!data.uiChanged) visual.push(`해당 없음 — ${cell(requiredText(data.visualNote, 'visualNote'))}`);
  else if (blocked) visual.push(`**캡처 대기 — ${cell(data.visualBlockedReason)}**\n\n실제 화면 확인 전까지 Draft로 유지합니다.`);
  else for (const shot of shots) {
    const title = requiredText(shot.title, 'screenshot.title');
    const note = requiredText(shot.note, 'screenshot.note');
    requireValue(shaPattern.test(shot.sourceCommit), '화면을 실행한 코드의 40자리 sourceCommit이 필요합니다.');
    if (shot.before) requireValue(shaPattern.test(shot.beforeSourceCommit), '전 화면을 실행한 beforeSourceCommit이 필요합니다.');
    const afterURL = evidenceURL(shot.after, context);
    const beforeURL = shot.before ? evidenceURL(shot.before, context) : null;
    const picture = (url, label) => `<a href="${html(url)}"><img src="${html(url)}" width="280" alt="${html(label)}"></a>`;
    visual.push(`**${cell(title)}** — ${cell(requiredText(shot.environment, 'screenshot.environment'))}`);
    visual.push(`| 변경 전 | 변경 후 |\n| --- | --- |\n| ${beforeURL ? picture(beforeURL, `${title} 변경 전`) : '신규 화면 — 이전 화면 없음'} | ${picture(afterURL, `${title} 변경 후`)} |`);
    visual.push(`${cell(note)}\n\n실행 코드: ${shot.before ? `전 \`${shot.beforeSourceCommit}\` / ` : ''}후 \`${shot.sourceCommit}\``);
  }
  const prototype = data.prototype;
  requireValue(prototype && ['not-deployed', 'deployed', 'not-applicable'].includes(prototype.status), 'prototype.status 값이 올바르지 않습니다.');
  let delivery = `${{ 'not-deployed': '미배포', deployed: '배포', 'not-applicable': '해당 없음' }[prototype.status]} — ${cell(requiredText(prototype.note, 'prototype.note'))}`;
  if (prototype.status === 'deployed') {
    delivery += `\n\n[설치 경로](${httpsURL(prototype.url, 'prototype.url')}) · ${cell(requiredText(prototype.build, 'prototype.build'))}\n\n설치 확인: ${cell(requiredText(prototype.installationCheck, 'prototype.installationCheck'))}`;
  }
  const remaining = rows(data.remaining, 'remaining', 0).map(item => `- ${cell(requiredText(item, 'remaining item'))}`);
  return [
    `<!-- ui-change: ${data.uiChanged ? 'yes' : 'no'} -->`,
    `<!-- review-status: ${data.draft ? 'blocked' : 'ready'} -->`,
    ...(data.draft ? ['> 작성 중입니다. 남은 검증을 확인한 뒤 리뷰 준비로 전환합니다.'] : []),
    '## 변경 요약', cell(summary), '| 이전 | 변경 후 |\n| --- | --- |\n' + changes.join('\n'),
    '## 적용한 규칙', '| 규칙 | 이번 PR의 적용 근거 |\n| --- | --- |\n' + rules.join('\n'),
    '## 화면 확인', visual.join('\n\n'),
    '## 검증', '| 확인한 것 | 결과 | 환경·근거 |\n| --- | --- | --- |\n' + checks.join('\n'),
    '## 프로토타입', delivery,
    '## 남은 작업', remaining.length ? remaining.join('\n') : '없음.',
    `<!-- report-commit: ${context.commit} -->`,
  ].join('\n\n') + '\n';
}

export function checkPR(body, draft) {
  const errors = [];
  const text = String(body ?? '').replaceAll('\r\n', '\n');
  const clean = text.replace(/<!--[\s\S]*?-->/g, '').trim();
  const chunks = clean.split(/^## ([^\n]+)\n/m);
  const content = new Map();
  for (let index = 1; index < chunks.length; index += 2) content.set(chunks[index].trim(), chunks[index + 1].trim());
  const contentFor = heading => content.get(heading) ?? '';
  for (const heading of sections) {
    const content = contentFor(heading);
    const lines = content.split('\n');
    // Discard table headings, separator rows, and blank cells; keep actual evidence.
    const meaningful = lines.filter((line, index) => {
      if (!/^\s*\|/.test(line)) return line.trim();
      if (/^\s*\|[\s|:-]+$/.test(lines[index + 1] ?? '')) return false;
      return !/^\s*\|[\s|:-]*$/.test(line);
    }).join('').trim();
    if (!meaningful) errors.push(`${heading}: 내용을 작성하세요.`);
  }
  const ui = text.match(/<!-- ui-change: (yes|no) -->/)?.[1];
  if (!ui) errors.push('ui-change를 yes 또는 no로 표시하세요.');
  const visual = contentFor('화면 확인');
  const hasImage = /<img\b[^>]*src="https:\/\/[^"\s]+"[^>]*>/i.test(visual) || /!\[[^\]]*\]\(https:\/\/[^\s)]+\)/.test(visual);
  if (ui === 'yes' && !hasImage && !draft) errors.push('UI 변경은 실행 화면을 첨부하거나 Draft로 전환하세요.');
  if (!draft && text.includes('<!-- review-status: blocked -->')) errors.push('검증 대기 보고서는 Draft로 유지하거나 검증 후 갱신하세요.');
  return errors;
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--check-pr') {
    const eventPath = process.env.GITHUB_EVENT_PATH;
    if (!eventPath) throw new Error('GITHUB_EVENT_PATH가 필요합니다.');
    const event = JSON.parse(readFileSync(eventPath, 'utf8'));
    if (!event.pull_request) return;
    const errors = checkPR(event.pull_request.body, event.pull_request.draft);
    requireValue(errors.length === 0, errors.join('\n'));
    console.log('PR 필수 항목 확인 완료. 화면의 진위·가독성과 앱 실행은 별도 리뷰 대상입니다.');
    return;
  }
  requireValue(args.length === 2, '사용법: node scripts/pr-report.mjs <입력 JSON> <출력 MD>');
  const git = (...parts) => execFileSync('git', parts, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const commit = git('rev-parse', 'HEAD');
  const origin = git('remote', 'get-url', 'origin');
  const match = origin.match(/^(?:https:\/\/github\.com\/|git@github\.com:)([\w.-]+\/[\w.-]+?)(?:\.git)?$/);
  requireValue(match, 'GitHub origin URL을 확인하세요. 인증정보를 URL에 넣지 마세요.');
  const data = JSON.parse(readFileSync(args[0], 'utf8').replace(/^\uFEFF/, ''));
  const body = renderReport(data, {
    repository: match[1], commit,
    readBlob(path) {
      try { return execFileSync('git', ['show', `${commit}:${path}`], { maxBuffer: 6 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] }); }
      catch { throw new Error(`커밋된 캡처를 찾을 수 없습니다: ${path}`); }
    },
  });
  mkdirSync(dirname(resolve(args[1])), { recursive: true });
  writeFileSync(args[1], body, 'utf8');
  console.log(`PR 본문 생성: ${args[1]}${data.draft ? ' (Draft로 게시)' : ''}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { main(); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
