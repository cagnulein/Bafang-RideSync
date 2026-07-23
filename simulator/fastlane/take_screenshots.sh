#!/bin/bash
# Screenshot per App Store via xcrun simctl + tap tramite osascript
# Richiede: Simulator.app aperto con i device Booted
set -euo pipefail

APP_PATH="build/ios/iphonesimulator/Runner.app"
BUNDLE_ID="org.cagnulein.eerg"
OUT_DIR="fastlane/screenshots"

IPHONE_PRO_MAX="75623206-6EA1-44B2-992A-6F45F1F687C2"
IPHONE_AIR="A99EEE8F-B9B6-4AB0-B834-48AAC1225989"

# Coordinate schermo Mac del pulsante Next/Get started nel Simulator
# iPhone Air è la prima finestra aperta (più piccola)
# iPhone Pro Max è la seconda finestra
NEXT_BTN_AIR_X=728
NEXT_BTN_AIR_Y=687
NEXT_BTN_PROMAX_X=750
NEXT_BTN_PROMAX_Y=697

LANGUAGES=("en-US")  # it usa gli stessi screenshot (app non localizzata)

# Build se necessario
if [ ! -d "$APP_PATH" ]; then
  echo "→ Building for simulator..."
  flutter build ios --simulator --no-codesign
fi

mkdir -p "$OUT_DIR/en-US" "$OUT_DIR/it"

# Tap nella finestra del Simulator via osascript
sim_tap() {
  local x=$1 y=$2
  osascript -e "tell application \"System Events\" to click at {$x, $y}" 2>/dev/null || true
}

# Screenshot simctl ad alta risoluzione
snap() {
  local device=$1 name=$2 lang=$3 idx=$4
  local dir="$OUT_DIR/$lang"; mkdir -p "$dir"
  xcrun simctl io "$device" screenshot "$dir/${idx}_${name}_${lang//\//_}.png" 2>/dev/null
  echo "  📸 $idx"
}

take_onboarding_shots() {
  local device=$1 dname=$2 next_x=$3 next_y=$4

  # Assicura Simulator.app aperto e visibile
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app 2>/dev/null || true
  sleep 2

  # Status bar
  xcrun simctl status_bar "$device" override \
    --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true

  # Reset app
  xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$device" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$device" "$APP_PATH"

  xcrun simctl launch "$device" "$BUNDLE_ID" \
    -AppleLanguages "(en-US)" -AppleLocale "en_US"
  sleep 5

  snap "$device" "$dname" "en-US" "01"
  sim_tap "$next_x" "$next_y"; sleep 2
  snap "$device" "$dname" "en-US" "02"
  sim_tap "$next_x" "$next_y"; sleep 2
  snap "$device" "$dname" "en-US" "03"
  sim_tap "$next_x" "$next_y"; sleep 2
  snap "$device" "$dname" "en-US" "04"
  sim_tap "$next_x" "$next_y"; sleep 3  # Get started → main screen
  snap "$device" "$dname" "en-US" "05"

  xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true
}

echo "══ iPhone Air ══════════════════════"
take_onboarding_shots "$IPHONE_AIR" "iPhone_Air" "$NEXT_BTN_AIR_X" "$NEXT_BTN_AIR_Y"

echo ""
echo "══ iPhone 17 Pro Max ═══════════════"
# Switcha il Simulator GUI al Pro Max
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
sleep 1
# Apri finestra Pro Max tramite AppleScript menu Window
osascript << 'EOF' 2>/dev/null || true
tell application "System Events"
  tell process "Simulator"
    click menu item "iPhone 17 Pro Max – iOS 26.5" of menu "Window" of menu bar 1
  end tell
end tell
EOF
sleep 2
take_onboarding_shots "$IPHONE_PRO_MAX" "iPhone_17_Pro_Max" "$NEXT_BTN_PROMAX_X" "$NEXT_BTN_PROMAX_Y"

# Copia en-US come it (app non localizzata in italiano)
echo ""
echo "→ Copiando en-US → it (app non localizzata)"
for f in "$OUT_DIR/en-US/"*.png; do
  base=$(basename "$f" | sed 's/_en-US/_it/')
  cp "$f" "$OUT_DIR/it/$base"
done

echo ""
echo "✅ Screenshot salvati in $OUT_DIR"
find "$OUT_DIR" -name "*.png" | sort
