#!/usr/bin/env bash

set -o pipefail

readonly BUNDLE_ID="com.kkape.mynas"
readonly CONTAINER_DATA_DIR="${HOME}/Library/Containers/${BUNDLE_ID}/Data"
readonly APP_SUPPORT_DIR="${HOME}/Library/Application Support/${BUNDLE_ID}"

echo "正在清理 $BUNDLE_ID 的本地数据..."

# macOS protects the container metadata file even from its owner. Removing the
# writable Data directory clears the app sandbox without producing a misleading
# "Operation not permitted" error for that system-managed metadata file.
if [[ -d "$CONTAINER_DATA_DIR" ]]; then
  rm -rf -- "$CONTAINER_DATA_DIR"
fi
if [[ -d "$APP_SUPPORT_DIR" ]]; then
  rm -rf -- "$APP_SUPPORT_DIR"
fi

echo "开始全新的 Flutter 运行..."
flutter run -d macos 2>&1 | tee macos.log
