#!/usr/bin/env bash
# Run this script once from inside the simulator/ directory:
#   cd simulator && bash setup_macos.sh
#
# It runs `flutter create` to generate the macOS boilerplate, then patches
# the entitlements and Info.plist for Bluetooth access.

set -e
cd "$(dirname "$0")"

echo "==> Running flutter create to generate macOS boilerplate…"
flutter create . \
  --org com.bafang \
  --project-name bafang_ride_sync_sim \
  --platforms=macos \
  --no-overwrite

echo ""
echo "==> Patching macos/Runner/Info.plist for Bluetooth permission…"
/usr/libexec/PlistBuddy -c \
  "Add :NSBluetoothAlwaysUsageDescription string 'Used to connect to the Bafang EKD01-BF e-bike display'" \
  macos/Runner/Info.plist 2>/dev/null || \
/usr/libexec/PlistBuddy -c \
  "Set :NSBluetoothAlwaysUsageDescription 'Used to connect to the Bafang EKD01-BF e-bike display'" \
  macos/Runner/Info.plist

echo ""
echo "==> Installing Flutter dependencies…"
flutter pub get

echo ""
echo "==> All done. Run the app with:"
echo "    flutter run -d macos"
echo ""
echo "    Or open the Xcode project:"
echo "    open macos/Runner.xcworkspace"
