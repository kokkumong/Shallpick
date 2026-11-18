#!/bin/zsh
# 무료 Apple ID(Personal Team)로 케이블 연결한 아이폰에 Shallpick 을 빌드해서 설치합니다.
# 프로젝트 설정(pbxproj, 기존 entitlements)은 건드리지 않고 이번 빌드에만 값을 덮어써요.
#
# 사용법:
#   scripts/install-on-iphone.sh            # 연결된 아이폰이 하나면 자동 선택
#   scripts/install-on-iphone.sh <UDID>     # 여러 대일 때 지정
#   scripts/install-on-iphone.sh --list     # 연결된 기기 목록만 보기
#
# 주의: 무료 계정으로 설치한 앱은 7일 뒤 열리지 않아요. 그때 이 스크립트를 다시 돌리면 됩니다.
set -euo pipefail

TEAM_ID="LS2JQL7GHW"   # Xcode 에 로그인된 Personal Team
ROOT="${0:A:h:h}"
DERIVED="$ROOT/build/device"
APP="$DERIVED/Build/Products/Release-iphoneos/Shallpick.app"

cd "$ROOT"

# 연결돼 있고 사용 가능한 실제 아이폰/아이패드 목록 (UDID 이름)
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

if [[ "${1:-}" == "--list" ]]; then
  list_devices
  exit 0
fi

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  devices=("${(@f)$(list_devices)}")
  devices=(${devices:#})
  if (( ${#devices} == 0 )); then
    echo "❌ 연결된 아이폰을 못 찾았어요."
    echo "   - 케이블로 연결하고 아이폰 잠금을 푼 뒤 '이 컴퓨터를 신뢰'를 눌렀는지"
    echo "   - 설정 > 개인정보 보호 및 보안 > 개발자 모드 를 켜고 재부팅했는지 확인해 주세요."
    exit 1
  elif (( ${#devices} > 1 )); then
    echo "기기가 여러 대 연결돼 있어요. UDID 를 골라서 다시 실행해 주세요:"
    printf '  %s\n' "${devices[@]}"
    exit 1
  fi
  UDID="${devices[1]%%$'\t'*}"
  echo "📱 ${devices[1]}"
fi

echo "🔨 빌드 중 (Release, Personal Team)…"
xcodebuild \
  -project Shallpick.xcodeproj \
  -scheme Shallpick \
  -configuration Release \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS=Config/Shallpick.free.entitlements \
  -quiet \
  build

echo "📲 설치 중…"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "🚀 실행 중…"
if ! xcrun devicectl device process launch --device "$UDID" com.kokkumong.Shallpick >/dev/null 2>&1; then
  echo "⚠️  설치는 됐는데 실행이 막혔어요. 아이폰에서"
  echo "   설정 > 일반 > VPN 및 기기 관리 > (내 Apple ID) > 신뢰 를 누른 뒤 앱을 직접 열어 주세요."
  exit 0
fi
echo "✅ 끝! 아이폰에서 Shallpick 이 열렸어요. (7일 뒤 다시 설치 필요)"
