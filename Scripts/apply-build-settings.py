import pathlib, re, sys

pbx = pathlib.Path("Homassy.xcodeproj/project.pbxproj")
text = pbx.read_text()

def edit(text, owner, set_keys, remove_keys):
    pattern = re.compile(
        r"(/\* (?:Debug|Release) configuration for " + re.escape(owner) + r" \*/ = \{\n"
        r"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{\n)(.*?)(\n\t\t\t\};)",
        re.S,
    )
    def fix(match):
        kept = []
        for line in match.group(2).split("\n"):
            key = line.strip().split(" = ", 1)[0].strip('"')
            if key in set_keys or key in remove_keys:
                if not line.rstrip().endswith(";"):
                    sys.exit(f"{owner}: {key} spans several lines; change it in Xcode instead")
                continue
            kept.append(line)
        kept += [f"\t\t\t\t{key} = {value};" for key, value in set_keys.items()]
        return match.group(1) + "\n".join(kept) + match.group(3)
    new_text, count = pattern.subn(fix, text)
    if count != 2:
        sys.exit(f"{owner}: expected Debug and Release configurations, found {count}")
    return new_text

common = {
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}
drop_platforms = {"MACOSX_DEPLOYMENT_TARGET", "XROS_DEPLOYMENT_TARGET", "TVOS_DEPLOYMENT_TARGET",
                  "WATCHOS_DEPLOYMENT_TARGET", "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]"}

text = edit(text, 'PBXProject "Homassy"', {"IPHONEOS_DEPLOYMENT_TARGET": "26.0"}, drop_platforms)

text = edit(text, 'PBXNativeTarget "Homassy"', {
    **common,
    "PRODUCT_BUNDLE_IDENTIFIER": "com.homassy.app",
    "INFOPLIST_FILE": "Homassy/Info.plist",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
}, drop_platforms | {"INFOPLIST_KEY_UISupportedInterfaceOrientations", "ENABLE_APP_SANDBOX", "ENABLE_USER_SELECTED_FILES",
                     "CODE_SIGN_ENTITLEMENTS"})

text = edit(text, 'PBXNativeTarget "HomassyUITests"', {
    **common,
    "PRODUCT_BUNDLE_IDENTIFIER": "com.homassy.app.uitests",
}, drop_platforms)

# Widget extension (N-04): same language and isolation settings as the app, so shared files compile the same way.
text = edit(text, 'PBXNativeTarget "HomassyWidgetsExtension"', {
    **common,
    "PRODUCT_BUNDLE_IDENTIFIER": "com.homassy.app.widgets",
    "INFOPLIST_KEY_CFBundleDisplayName": "Homassy",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
}, drop_platforms)

# Free-team fallback (Step 15a): HOMASSY_DEV_BUNDLE_ID=1 gives Debug the `.dev` bundle IDs; Release keeps the permanent ones.
import os
if os.environ.get("HOMASSY_DEV_BUNDLE_ID") == "1":
    for owner, dev_id in (('PBXNativeTarget "Homassy"', "com.homassy.app.dev"),
                          ('PBXNativeTarget "HomassyUITests"', "com.homassy.app.dev.uitests"),
                          ('PBXNativeTarget "HomassyWidgetsExtension"', "com.homassy.app.dev.widgets")):
        block = re.compile(r"(/\* Debug configuration for " + re.escape(owner) + r" \*/ = \{.*?PRODUCT_BUNDLE_IDENTIFIER = )[^;]+;", re.S)
        text, n = block.subn(lambda m: m.group(1) + dev_id + ";", text, count=1)
        if n != 1:
            sys.exit(f"{owner}: Debug PRODUCT_BUNDLE_IDENTIFIER not found")

pbx.write_text(text)
print("pbxproj updated")
