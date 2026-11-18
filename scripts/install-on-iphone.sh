#!/bin/zsh
# 무료 Apple ID(Personal Team)로 케이블 연결한 아이폰에 Shallpick 을 빌드해서 설치합니다.
# 프로젝트 설정(pbxproj, 기존 entitlements)은 건드리지 않고 이번 빌드에만 값을 덮어써요.
#
# 사용법:
#   scripts/install-on-iphone.sh                          # 연결된 아이폰이 하나면 자동 선택
#   scripts/install-on-iphone.sh <UDID>                   # 여러 대일 때 지정
#   scripts/install-on-iphone.sh --list                   # 연결된 기기 목록만 보기
#   scripts/install-on-iphone.sh --check                  # 설치 전 준비 상태만 점검
#   SHALLPICK_BUNDLE_ID=com.kokkumong.Shallpick.t1 scripts/install-on-iphone.sh
#
# 번들 ID: 무료 계정은 한 번들 ID 를 한 Apple ID 만 쓸 수 있어요.
#   - com.kokkumong.Shallpick 은 kokkumong 계정 전용
#   - 다른 팀원은 팀장에게 받은 번들 ID 를 SHALLPICK_BUNDLE_ID 로 넘겨 주세요.
#     (카카오 로그인을 위해 Kakao Developers 에 미리 등록된 ID 여야 해요)
#
# 팀 ID: Xcode > Settings > Accounts 에 로그인된 Personal Team 을 자동으로 찾아요.
#   여러 개면 SHALLPICK_TEAM_ID 로 지정.
#
# 주의: 무료 계정으로 설치한 앱은 7일 뒤 열리지 않아요. 그때 이 스크립트를 다시 돌리면 됩니다.
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED="$ROOT/build/device"
APP="$DERIVED/Build/Products/Release-iphoneos/Shallpick.app"
BUNDLE_ID="${SHALLPICK_BUNDLE_ID:-com.kokkumong.Shallpick}"

cd "$ROOT"

# ---------- 준비 상태 점검 ----------

# Xcode 에 로그인된 팀 목록: "팀ID<TAB>팀이름<TAB>personal|paid"
list_teams() {
  defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -I -c '
import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
seen = set()
for teams in d.get("IDEProvisioningTeamByIdentifier", {}).values():
    for t in teams:
        tid = t.get("teamID")
        if not tid or tid in seen:
            continue
        seen.add(tid)
        kind = "personal" if t.get("isFreeProvisioningTeam") else "paid"
        print(tid, t.get("teamName", ""), kind, sep="\t")
' || true
}

pick_team() {
  if [[ -n "${SHALLPICK_TEAM_ID:-}" ]]; then
    echo "$SHALLPICK_TEAM_ID"; return
  fi
  local teams; teams=("${(@f)$(list_teams)}"); teams=(${teams:#})
  local personal=(${(M)teams:#*$'\t'personal})
  if (( ${#personal} == 1 )); then
    echo "${personal[1]%%$'\t'*}"
  elif (( ${#teams} == 1 )); then
    echo "${teams[1]%%$'\t'*}"
  fi
}

check_ready() {
  local ok=1
  if [[ "$(xcode-select -p 2>/dev/null)" != *Xcode*.app* ]]; then
    echo "❌ Xcode 앱이 선택돼 있지 않아요. App Store 에서 Xcode 를 설치하고 한 번 실행한 뒤"
    echo "   터미널에서: sudo xcode-select -s /Applications/Xcode.app"
    ok=0
  elif ! xcodebuild -showsdks 2>/dev/null | grep -q "iphoneos"; then
    echo "❌ Xcode 에 iOS 플랫폼이 없어요. Xcode > Settings > Components 에서 iOS 를 받아 주세요."
    ok=0
  fi

  if [[ ! -f Config/Secrets.xcconfig ]] || ! grep -qE "^SUPABASE_KEY *= *\S" Config/Secrets.xcconfig; then
    echo "❌ Config/Secrets.xcconfig 가 없거나 비어 있어요. 팀장에게 받은 파일을 Config 폴더에 넣어 주세요."
    ok=0
  fi

  TEAM_ID="$(pick_team)"
  if [[ -z "$TEAM_ID" ]]; then
    if [[ -z "$(list_teams)" ]]; then
      echo "❌ Xcode 에 Apple ID 가 로그인돼 있지 않아요."
      echo "   Xcode > Settings(⌘,) > Accounts > 왼쪽 아래 + > Apple ID 로 로그인해 주세요."
    else
      echo "❌ Xcode 에 팀이 여러 개라 고르지 못했어요. SHALLPICK_TEAM_ID 로 지정해 주세요:"
      list_teams | sed 's/^/   /'
    fi
    ok=0
  fi

  if [[ "$BUNDLE_ID" == "com.kokkumong.Shallpick" && -n "$TEAM_ID" && "$TEAM_ID" != "LS2JQL7GHW" ]]; then
    echo "❌ com.kokkumong.Shallpick 은 다른 사람 계정에 등록된 번들 ID 라 쓸 수 없어요."
    echo "   팀장에게 받은 번들 ID 로 실행해 주세요: SHALLPICK_BUNDLE_ID=<받은 ID> scripts/install-on-iphone.sh"
    ok=0
  fi

  (( ok )) || exit 1
  echo "✅ 준비 완료 — 팀 $TEAM_ID / 번들 ID $BUNDLE_ID"
}

# ---------- 기기 ----------

# 연결된 실제 아이폰/아이패드 목록 (UDID 이름 iOS버전)
list_devices() {
  local json; json=$(mktemp)
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  /usr/bin/python3 -I - "$json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    # 지금 연결돼 있지 않은 기기는 tunnelState 가 unavailable
    if hw.get("reality") != "physical" or conn.get("tunnelState") == "unavailable":
        continue
    name = d.get("deviceProperties", {}).get("name", "?")
    os = d.get("deviceProperties", {}).get("osVersionNumber", "?")
    note = "" if os.split(".")[0].isdigit() and int(os.split(".")[0]) >= 26 else "  ⚠️ iOS 26 이상이어야 설치돼요"
    print(f'{hw.get("udid")}\t{name}\tiOS {os}{note}')
PY
  rm -f "$json"
}

dev_mode() {
  local json; json=$(mktemp)
  xcrun devicectl device info details --device "$UDID" --json-output "$json" >/dev/null 2>&1 || true
  /usr/bin/python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1]))["result"]["deviceProperties"].get("developerModeStatus",""))
except Exception: print("")' "$json"
  rm -f "$json"
}

case "${1:-}" in
  --list) list_devices; exit 0 ;;
  --check) check_ready; exit 0 ;;
esac

check_ready

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  devices=("${(@f)$(list_devices)}")
  devices=(${devices:#})
  if (( ${#devices} == 0 )); then
    echo "❌ 연결된 아이폰을 못 찾았어요."
    echo "   - 케이블로 연결하고 아이폰 잠금을 푼 뒤 '이 컴퓨터를 신뢰'를 눌렀는지"
    echo "   - 재부팅 직후라면 잠금을 풀고 10초쯤 뒤에 다시 실행해 주세요."
    exit 1
  elif (( ${#devices} > 1 )); then
    echo "기기가 여러 대 연결돼 있어요. UDID 를 골라서 다시 실행해 주세요:"
    printf '  %s\n' "${devices[@]}"
    exit 1
  fi
  UDID="${devices[1]%%$'\t'*}"
  echo "📱 ${devices[1]}"
fi

if [[ "$(dev_mode)" == "disabled" ]]; then
  echo "❌ 아이폰의 개발자 모드가 꺼져 있어요."
  echo "   설정 > 개인정보 보호 및 보안 > (맨 아래) 개발자 모드 를 켜고 재부팅한 뒤,"
  echo "   재부팅 후 뜨는 '켜기' 창에서 한 번 더 켜기 + 암호 입력 → 다시 실행해 주세요."
  echo "   메뉴가 안 보이면 케이블을 뺐다 꽂고 '이 컴퓨터를 신뢰'를 다시 눌러 주세요."
  exit 1
fi

echo "🔨 빌드 중 (Release, 팀 $TEAM_ID)… 처음엔 5~10분 걸려요."
xcodebuild \
  -project Shallpick.xcodeproj \
  -scheme Shallpick \
  -configuration Release \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS=Config/Shallpick.free.entitlements \
  -quiet \
  build

echo "📲 설치 중…"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "🚀 실행 중…"
if ! xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "⚠️  설치는 됐는데 실행이 막혔어요. 아이폰에서"
  echo "   설정 > 일반 > VPN 및 기기 관리 > (설치한 사람의 Apple ID) > 신뢰 를 누른 뒤 앱을 직접 열어 주세요."
  exit 0
fi
echo "✅ 끝! 아이폰에서 Shallpick 이 열렸어요. (7일 뒤 다시 설치 필요)"
