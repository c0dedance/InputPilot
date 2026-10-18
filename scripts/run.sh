#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]] || [[ $# -eq 1 && "$1" != "--build-only" && "$1" != "--dmg" ]]; then
    printf '%s\n' '用法：bash scripts/run.sh [--build-only | --dmg]' >&2
    exit 2
fi

INPUTPILOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUTPILOT_APP="$INPUTPILOT_ROOT/dist/InputPilot.app"

if /usr/bin/pgrep -x InputPilot >/dev/null; then
    printf '%s\n' '自动切换输入法仍在运行。请先点击其菜单栏 → 退出，然后重试。' >&2
    exit 1
else
    INPUTPILOT_PGREP_STATUS=$?
    if [[ $INPUTPILOT_PGREP_STATUS -ne 1 ]]; then
        printf '%s\n' '无法检查自动切换输入法进程；已停止构建。' >&2
        exit "$INPUTPILOT_PGREP_STATUS"
    fi
fi

cd "$INPUTPILOT_ROOT"
/usr/bin/xcrun swift build -c release
INPUTPILOT_BIN="$(/usr/bin/xcrun swift build -c release --show-bin-path)"

if [[ -e "$INPUTPILOT_APP" ]]; then
    INPUTPILOT_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INPUTPILOT_APP/Contents/Info.plist")"
    if [[ "$INPUTPILOT_EXISTING_ID" != "local.inputpilot.app" ]]; then
        printf '%s\n' 'dist 中已有其他应用；为防止覆盖，已停止。' >&2
        exit 1
    fi
fi

/bin/mkdir -p "$INPUTPILOT_APP/Contents/MacOS"
/bin/mkdir -p "$INPUTPILOT_APP/Contents/Resources"
/bin/cp "$INPUTPILOT_ROOT/Resources/AppIcon.icns" "$INPUTPILOT_APP/Contents/Resources/AppIcon.icns"
/bin/cp "$INPUTPILOT_ROOT/Resources/MenuBarIcon.pdf" "$INPUTPILOT_APP/Contents/Resources/MenuBarIcon.pdf"
/bin/cp "$INPUTPILOT_BIN/InputPilot" "$INPUTPILOT_APP/Contents/MacOS/InputPilot"
/bin/cp "$INPUTPILOT_ROOT/Resources/Info.plist" "$INPUTPILOT_APP/Contents/Info.plist"
/bin/mkdir -p "$INPUTPILOT_APP/Contents/Resources/zh-Hans.lproj"
/bin/cp "$INPUTPILOT_ROOT/Resources/zh-Hans.lproj/InfoPlist.strings" "$INPUTPILOT_APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
/usr/bin/plutil -lint "$INPUTPILOT_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$INPUTPILOT_APP"
/usr/bin/codesign --verify --strict --verbose=2 "$INPUTPILOT_APP"
printf '构建和本地签名校验通过：%s\n' "$INPUTPILOT_APP"

if [[ $# -eq 1 && "$1" == "--dmg" ]]; then
    INPUTPILOT_STAGE="$(/usr/bin/mktemp -d -t inputpilot-dmg)"
    trap '/bin/rm -rf -- "$INPUTPILOT_STAGE"' EXIT
    /usr/bin/ditto "$INPUTPILOT_APP" "$INPUTPILOT_STAGE/InputPilot.app"
    /bin/ln -s /Applications "$INPUTPILOT_STAGE/Applications"
    INPUTPILOT_DMG="$INPUTPILOT_ROOT/dist/InputPilot.dmg"
    /usr/bin/hdiutil create -volname '自动切换输入法' -srcfolder "$INPUTPILOT_STAGE" -format UDZO -ov "$INPUTPILOT_DMG"
    /usr/bin/hdiutil verify "$INPUTPILOT_DMG"
    printf '安装镜像已生成并通过校验：%s\n' "$INPUTPILOT_DMG"
fi

if [[ $# -eq 0 ]]; then
    /usr/bin/open "$INPUTPILOT_APP"
    printf '%s\n' '已请求打开。请查看屏幕顶部菜单栏的回环光标图标和输入源名称；没有 Dock 图标是正常的。'
else
    printf '%s\n' '仅构建，未启动应用，也未更改输入法或登录项。'
fi
