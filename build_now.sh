#!/bin/bash
export PATH="/home/z/flutter/bin:$PATH"
export GRADLE_USER_HOME=/tmp/ghome
export ANDROID_SDK_ROOT=/home/z/sdk
cd /home/z/my-project/download/photo_recover_ai
rm -rf build .dart_tool android/.gradle 2>/dev/null
echo "=== BUILD STARTED at $(date) ===" > /tmp/build_result.txt
flutter build apk --release --target-platform android-arm64 --shrink --tree-shake-icons >> /tmp/build_result.txt 2>&1
echo "=== BUILD ENDED at $(date) ===" >> /tmp/build_result.txt
if [ -f build/app/outputs/flutter-apk/app-release.apk ]; then
    ls -lh build/app/outputs/flutter-apk/app-release.apk >> /tmp/build_result.txt
    echo "SUCCESS" >> /tmp/build_result.txt
else
    echo "FAILED" >> /tmp/build_result.txt
fi
