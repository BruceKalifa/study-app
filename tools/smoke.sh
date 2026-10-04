#!/usr/bin/env bash
# Runs inside the emulator (android-emulator-runner): install release APK, launch, capture logs.
set -x
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=com.une.pulinote.study_app
mkdir -p ci-smoke
adb logcat -c
adb install -r "$APK" 2>&1 | tee ci-smoke/install.txt
adb shell am start -W -n "$PKG/.MainActivity" 2>&1 | tee ci-smoke/start.txt
sleep 25
{ echo "pid: $(adb shell pidof $PKG)"; adb shell dumpsys activity activities | grep -i -m5 "mResumedActivity\|topResumedActivity"; } > ci-smoke/state.txt 2>&1
adb exec-out screencap -p > ci-smoke/screen1.png
adb logcat -b crash -d > ci-smoke/crash.txt 2>&1
adb logcat -d > ci-smoke/logcat.txt 2>&1
adb logcat -d -s AndroidRuntime:E flutter:V DEBUG:F libc:F > ci-smoke/filtered.txt 2>&1
exit 0
