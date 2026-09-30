#!/usr/bin/env bash
# Verifies the Homassy build settings, Info.plist, local-mode signing rules and git-ignore rules.
# C-01 replaces the "Local-mode checks" block with cloud-mode checks.
# Usage: Scripts/check-project-settings.sh   (from the repository root)
set -u
cd "$(dirname "$0")/.."
fail=0

check_target() {
  local target=$1 expected=$2 cfg settings key want got
  for cfg in Debug Release; do
    settings=$(xcodebuild -project Homassy.xcodeproj -target "$target" -configuration "$cfg" -showBuildSettings 2>/dev/null)
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
INFOPLIST_FILE|Homassy/Info.plist
GENERATE_INFOPLIST_FILE|YES
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME|AccentColor
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone|UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad|UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'

UITEST_EXPECT='IPHONEOS_DEPLOYMENT_TARGET|26.0
SWIFT_VERSION|6.0
SWIFT_STRICT_CONCURRENCY|complete
TARGETED_DEVICE_FAMILY|1,2
SUPPORTED_PLATFORMS|iphoneos iphonesimulator
TEST_TARGET_NAME|Homassy'

WIDGET_EXPECT='IPHONEOS_DEPLOYMENT_TARGET|26.0
SWIFT_VERSION|6.0
SWIFT_STRICT_CONCURRENCY|complete
SWIFT_DEFAULT_ACTOR_ISOLATION|MainActor
SWIFT_APPROACHABLE_CONCURRENCY|YES
TARGETED_DEVICE_FAMILY|1,2
SUPPORTED_PLATFORMS|iphoneos iphonesimulator'

check_target Homassy "$APP_EXPECT"
check_target HomassyUITests "$UITEST_EXPECT"
check_target HomassyWidgetsExtension "$WIDGET_EXPECT"

setting() {  # setting <target> <config> <key>
  xcodebuild -project Homassy.xcodeproj -target "$1" -configuration "$2" -showBuildSettings 2>/dev/null \
    | awk -F' = ' -v k="$3" '{ name = $1; sub(/^ +/, "", name) } name == k { print $2; exit }'
}
# Bundle IDs: Release is always the permanent ID; Debug may carry the free-team `.dev` override (Step 15a).
expect_one_of() {  # expect_one_of <label> <got> <allowed...>
  local label=$1 got=$2; shift 2
  for want in "$@"; do [ "$got" = "$want" ] && return 0; done
  echo "FAIL $label: got '$got', want one of: $*"; fail=1
}
expect_one_of "Homassy/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting Homassy Release PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app
expect_one_of "Homassy/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting Homassy Debug PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app com.homassy.app.dev
expect_one_of "HomassyUITests/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting HomassyUITests Release PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app.uitests
expect_one_of "HomassyUITests/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting HomassyUITests Debug PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app.uitests com.homassy.app.dev.uitests
expect_one_of "HomassyWidgetsExtension/Release PRODUCT_BUNDLE_IDENTIFIER" "$(setting HomassyWidgetsExtension Release PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app.widgets
expect_one_of "HomassyWidgetsExtension/Debug PRODUCT_BUNDLE_IDENTIFIER" "$(setting HomassyWidgetsExtension Debug PRODUCT_BUNDLE_IDENTIFIER)" com.homassy.app.widgets com.homassy.app.dev.widgets

# --- Local-mode checks (C-01 replaces this block) ---
for cfg in Debug Release; do
  got=$(setting Homassy "$cfg" CODE_SIGN_ENTITLEMENTS)
  [ -z "$got" ] || { echo "FAIL Homassy/$cfg CODE_SIGN_ENTITLEMENTS must be empty before C-01, got '$got'"; fail=1; }
  conditions=$(setting Homassy "$cfg" SWIFT_ACTIVE_COMPILATION_CONDITIONS)
  case " $conditions " in *" CLOUDKIT_ENABLED "*) echo "FAIL Homassy/$cfg CLOUDKIT_ENABLED is set before C-01"; fail=1;; esac
done
[ ! -e Homassy/Homassy.entitlements ] || { echo "FAIL Homassy/Homassy.entitlements exists before C-01"; fail=1; }
for cfg in Debug Release; do
  got=$(setting HomassyWidgetsExtension "$cfg" CODE_SIGN_ENTITLEMENTS)
  [ -z "$got" ] || { echo "FAIL HomassyWidgetsExtension/$cfg CODE_SIGN_ENTITLEMENTS must be empty before N-05, got '$got'"; fail=1; }
done
# --- end local-mode checks ---

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
expect_plist() {
  local got; got=$(plist "$1" "$2")
  if [ "$got" != "$3" ]; then echo "FAIL $1 :$2: got '$got', want '$3'"; fail=1; fi
}
plutil -lint -s Homassy/Info.plist || fail=1
expect_plist Homassy/Info.plist CKSharingSupported true
# N-01: background app refresh. Plain Info.plist keys, no entitlement (works on the free Personal Team).
expect_plist Homassy/Info.plist BGTaskSchedulerPermittedIdentifiers:0 com.homassy.app.refresh
expect_plist Homassy/Info.plist UIBackgroundModes:0 fetch
# N-04: shopping Live Activity (no entitlement for local updates) and homassy:// links.
expect_plist Homassy/Info.plist NSSupportsLiveActivities true
expect_plist Homassy/Info.plist CFBundleURLTypes:0:CFBundleURLSchemes:0 homassy
if [ ! -f Homassy.xcodeproj/xcshareddata/xcschemes/HomassyWidgetsExtension.xcscheme ]; then
  echo "FAIL HomassyWidgetsExtension scheme is not shared"; fail=1
fi
grep -q 'productName = HomassyShared' Homassy.xcodeproj/project.pbxproj || { echo "FAIL HomassyShared is not linked"; fail=1; }

for path in HomassyKit/Package.swift HomassyKit/Sources/HomassyCore/HomassyCore.swift HomassyUITests/HomassyUITests.swift Scripts/check-project-settings.sh; do
  if git check-ignore -q "$path"; then echo "FAIL $path is git-ignored"; fail=1; fi
done

if [ -e Homassy/MyApp.swift ]; then echo "FAIL Homassy/MyApp.swift still exists"; fail=1; fi
if [ -e HomassyUITests/HomassyUITestsLaunchTests.swift ]; then echo "FAIL template launch tests still exist"; fail=1; fi
if [ ! -f Homassy.xcodeproj/xcshareddata/xcschemes/Homassy.xcscheme ]; then echo "FAIL Homassy scheme is not shared"; fail=1
elif ! grep -q 'BuildableName = "HomassyUITests.xctest"' Homassy.xcodeproj/xcshareddata/xcschemes/Homassy.xcscheme; then
  echo "FAIL HomassyUITests is not in the shared Homassy scheme"; fail=1
fi
if ! grep -q 'XCLocalSwiftPackageReference "HomassyKit"' Homassy.xcodeproj/project.pbxproj; then echo "FAIL HomassyKit is not a local package of the project"; fail=1; fi

if [ $fail -eq 0 ]; then echo "PROJECT SETTINGS OK"; else echo "PROJECT SETTINGS FAILED"; fi
exit $fail
