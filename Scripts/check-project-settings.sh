#!/usr/bin/env bash
# Verifies the Larari build settings, Info.plist, the cloud configuration (entitlements, CLOUDKIT_ENABLED,
# permanent bundle IDs; C-01) and git-ignore rules.
# Usage: Scripts/check-project-settings.sh   (from the repository root)
set -u
cd "$(dirname "$0")/.."
fail=0

check_target() {
  local target=$1 expected=$2 cfg settings key want got
  for cfg in Debug Release; do
    settings=$(xcodebuild -project Larari.xcodeproj -target "$target" -configuration "$cfg" -showBuildSettings 2>/dev/null)
    if [ -z "$settings" ]; then echo "FAIL $target/$cfg: no build settings (target missing?)"; fail=1; continue; fi
    while IFS='|' read -r key want; do
      [ -z "$key" ] && continue
      got=$(printf '%s\n' "$settings" | awk -F' = ' -v k="$key" '{ name = $1; sub(/^ +/, "", name) } name == k { print $2; exit }')
      if [ "$got" != "$want" ]; then echo "FAIL $target/$cfg $key: got '$got', want '$want'"; fail=1; fi
    done <<< "$expected"
  done
}

APP_EXPECT='IPHONEOS_DEPLOYMENT_TARGET|26.0
SWIFT_VERSION|6.0
SWIFT_STRICT_CONCURRENCY|complete
TARGETED_DEVICE_FAMILY|1,2
SUPPORTED_PLATFORMS|iphoneos iphonesimulator
SUPPORTS_MACCATALYST|NO
SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD|NO
SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD|NO
INFOPLIST_FILE|Larari/Info.plist
GENERATE_INFOPLIST_FILE|YES
INFOPLIST_KEY_UIApplicationSceneManifest_Generation|YES
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME|AccentColor
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone|UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad|UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'

UITEST_EXPECT='IPHONEOS_DEPLOYMENT_TARGET|26.0
SWIFT_VERSION|6.0
SWIFT_STRICT_CONCURRENCY|complete
TARGETED_DEVICE_FAMILY|1,2
SUPPORTED_PLATFORMS|iphoneos iphonesimulator
TEST_TARGET_NAME|Larari'

WIDGET_EXPECT='IPHONEOS_DEPLOYMENT_TARGET|26.0
SWIFT_VERSION|6.0
SWIFT_STRICT_CONCURRENCY|complete
SWIFT_DEFAULT_ACTOR_ISOLATION|MainActor
SWIFT_APPROACHABLE_CONCURRENCY|YES
TARGETED_DEVICE_FAMILY|1,2
SUPPORTED_PLATFORMS|iphoneos iphonesimulator'

check_target Larari "$APP_EXPECT"
check_target LarariUITests "$UITEST_EXPECT"
check_target LarariWidgetsExtension "$WIDGET_EXPECT"

setting() {  # setting <target> <config> <key>
  xcodebuild -project Larari.xcodeproj -target "$1" -configuration "$2" -showBuildSettings 2>/dev/null \
    | awk -F' = ' -v k="$3" '{ name = $1; sub(/^ +/, "", name) } name == k { print $2; exit }'
}
# Bundle IDs: the permanent IDs in both configurations (C-01 dropped the free-team `.dev` override).
expect_one_of() {  # expect_one_of <label> <got> <allowed...>
  local label=$1 got=$2; shift 2
  for want in "$@"; do [ "$got" = "$want" ] && return 0; done
  echo "FAIL $label: got '$got', want one of: $*"; fail=1
}
expect_one_of "Larari/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting Larari Release PRODUCT_BUNDLE_IDENTIFIER)" app.larari
expect_one_of "Larari/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting Larari Debug PRODUCT_BUNDLE_IDENTIFIER)" app.larari
expect_one_of "LarariUITests/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting LarariUITests Release PRODUCT_BUNDLE_IDENTIFIER)" app.larari.uitests
expect_one_of "LarariUITests/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting LarariUITests Debug PRODUCT_BUNDLE_IDENTIFIER)" app.larari.uitests
expect_one_of "LarariWidgetsExtension/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting LarariWidgetsExtension Release PRODUCT_BUNDLE_IDENTIFIER)" app.larari.widgets
expect_one_of "LarariWidgetsExtension/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting LarariWidgetsExtension Debug PRODUCT_BUNDLE_IDENTIFIER)" app.larari.widgets

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
expect_plist() {
  local got; got=$(plist "$1" "$2")
  if [ "$got" != "$3" ]; then echo "FAIL $1 :$2: got '$got', want '$3'"; fail=1; fi
}
# --- Cloud-mode checks (C-01) ---
for cfg in Debug Release; do
  got=$(setting Larari "$cfg" CODE_SIGN_ENTITLEMENTS)
  [ "$got" = "Larari/Larari.entitlements" ] || { echo "FAIL Larari/$cfg CODE_SIGN_ENTITLEMENTS: got '$got'"; fail=1; }
  conditions=$(setting Larari "$cfg" SWIFT_ACTIVE_COMPILATION_CONDITIONS)
  case " $conditions " in *" CLOUDKIT_ENABLED "*) ;; *) echo "FAIL Larari/$cfg CLOUDKIT_ENABLED is not set: '$conditions'"; fail=1;; esac
done
plutil -lint -s Larari/Larari.entitlements || fail=1
expect_plist Larari/Larari.entitlements com.apple.developer.icloud-container-identifiers:0 iCloud.app.larari
expect_plist Larari/Larari.entitlements com.apple.developer.icloud-services:0 CloudKit
expect_plist Larari/Larari.entitlements aps-environment development
expect_plist Larari/Larari.entitlements com.apple.security.application-groups:0 group.app.larari
expect_plist Larari/Info.plist UIBackgroundModes:1 remote-notification
# --- end cloud-mode checks ---
plutil -lint -s Larari/Info.plist || fail=1
expect_plist Larari/Info.plist CKSharingSupported true
# N-03: iPad windows. Explicit, so a settings change cannot turn multiple windows off silently. A dragged card
# carries the window activity, so it must be declared.
expect_plist Larari/Info.plist UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes true
expect_plist Larari/Info.plist NSUserActivityTypes:0 app.larari.window
# N-01: background app refresh. Plain Info.plist keys, no entitlement (works on the free Personal Team).
expect_plist Larari/Info.plist BGTaskSchedulerPermittedIdentifiers:0 app.larari.refresh
expect_plist Larari/Info.plist UIBackgroundModes:0 fetch
# N-04: shopping Live Activity (no entitlement for local updates) and larari:// links.
expect_plist Larari/Info.plist NSSupportsLiveActivities true
expect_plist Larari/Info.plist CFBundleURLTypes:0:CFBundleURLSchemes:0 larari
if [ ! -f Larari.xcodeproj/xcshareddata/xcschemes/LarariWidgetsExtension.xcscheme ]; then
  echo "FAIL LarariWidgetsExtension scheme is not shared"; fail=1
fi
grep -q 'productName = LarariShared' Larari.xcodeproj/project.pbxproj || { echo "FAIL LarariShared is not linked"; fail=1; }

for path in LarariKit/Package.swift LarariKit/Sources/LarariCore/LarariCore.swift LarariUITests/LarariUITests.swift Scripts/check-project-settings.sh; do
  if git check-ignore -q "$path"; then echo "FAIL $path is git-ignored"; fail=1; fi
done

if [ -e Larari/MyApp.swift ]; then echo "FAIL Larari/MyApp.swift still exists"; fail=1; fi
if [ -e LarariUITests/LarariUITestsLaunchTests.swift ]; then echo "FAIL template launch tests still exist"; fail=1; fi
if [ ! -f Larari.xcodeproj/xcshareddata/xcschemes/Larari.xcscheme ]; then echo "FAIL Larari scheme is not shared"; fail=1
elif ! grep -q 'BuildableName = "LarariUITests.xctest"' Larari.xcodeproj/xcshareddata/xcschemes/Larari.xcscheme; then
  echo "FAIL LarariUITests is not in the shared Larari scheme"; fail=1
fi
if ! grep -q 'XCLocalSwiftPackageReference "LarariKit"' Larari.xcodeproj/project.pbxproj; then echo "FAIL LarariKit is not a local package of the project"; fail=1; fi

if [ $fail -eq 0 ]; then echo "PROJECT SETTINGS OK"; else echo "PROJECT SETTINGS FAILED"; fi
exit $fail
