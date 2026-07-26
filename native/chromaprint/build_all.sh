#!/bin/bash
# Chromaprint 移动端完整构建脚本
# 用法: ./build_all.sh [ios|android|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CHROMAPRINT_VERSION="1.5.1"
CHROMAPRINT_SRC="$BUILD_DIR/chromaprint"
KISSFFT_SRC="$BUILD_DIR/kissfft"

echo "========================================"
echo "  Chromaprint 移动端构建脚本"
echo "========================================"
echo "项目根目录: $PROJECT_ROOT"
echo "构建目录: $BUILD_DIR"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 检查依赖
check_dependencies() {
    echo "=== 检查依赖 ==="

    if ! command -v cmake &> /dev/null; then
        echo "错误: cmake 未安装"
        echo "请运行: brew install cmake"
        exit 1
    fi
    echo "✓ cmake $(cmake --version | head -1)"

    if ! command -v xcodebuild &> /dev/null; then
        echo "错误: Xcode 未安装"
        exit 1
    fi
    echo "✓ $(xcodebuild -version | head -1)"

    echo ""
}

# 下载源码
download_sources() {
    echo "=== 下载源码 ==="
    mkdir -p "$BUILD_DIR"

    # Chromaprint
    if [ ! -d "$CHROMAPRINT_SRC" ]; then
        echo "下载 Chromaprint v$CHROMAPRINT_VERSION..."
        git clone --depth 1 --branch "v$CHROMAPRINT_VERSION" \
            https://github.com/acoustid/chromaprint.git "$CHROMAPRINT_SRC"
        # 删除 .git 目录，避免 IDE 识别为独立仓库
        rm -rf "$CHROMAPRINT_SRC/.git"
    else
        echo "✓ Chromaprint 源码已存在"
    fi

    # KissFFT
    if [ ! -d "$KISSFFT_SRC" ]; then
        echo "下载 KissFFT..."
        git clone --depth 1 https://github.com/mborgerding/kissfft.git "$KISSFFT_SRC"
        # 删除 .git 目录，避免 IDE 识别为独立仓库
        rm -rf "$KISSFFT_SRC/.git"
    else
        echo "✓ KissFFT 源码已存在"
    fi

    # 修复 KissFFT 目录结构 (新版本文件位置变了)
    echo "修复 KissFFT 目录结构..."
    cd "$KISSFFT_SRC/tools"
    for file in kiss_fftr.c kiss_fftr.h kiss_fft.c kiss_fft.h _kiss_fft_guts.h; do
        if [ -f "../$file" ] && [ ! -e "$file" ]; then
            ln -sf "../$file" "$file"
            echo "  链接 $file"
        fi
    done

    echo ""
}

# 编译 iOS
build_ios() {
    echo "=== 编译 iOS ==="

    local IOS_OUTPUT="$OUTPUT_DIR/ios"
    mkdir -p "$IOS_OUTPUT"

    # 清理旧构建
    rm -rf "$CHROMAPRINT_SRC/build-ios-device"
    rm -rf "$CHROMAPRINT_SRC/build-ios-sim"

    # iOS Device (arm64)
    echo "编译 iOS Device (arm64)..."
    mkdir -p "$CHROMAPRINT_SRC/build-ios-device"
    cd "$CHROMAPRINT_SRC/build-ios-device"

    cmake .. \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_TESTS=OFF \
        -DFFT_LIB=kissfft \
        -DKISSFFT_SOURCE_DIR="$KISSFFT_SRC" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    cmake --build . --config Release

    # iOS Simulator (arm64 + x86_64)
    echo "编译 iOS Simulator..."
    mkdir -p "$CHROMAPRINT_SRC/build-ios-sim"
    cd "$CHROMAPRINT_SRC/build-ios-sim"

    cmake .. \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphonesimulator \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_TESTS=OFF \
        -DFFT_LIB=kissfft \
        -DKISSFFT_SOURCE_DIR="$KISSFFT_SRC" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    cmake --build . --config Release

    # 创建 xcframework
    echo "创建 xcframework..."

    DEVICE_LIB=$(find "$CHROMAPRINT_SRC/build-ios-device" -name "libchromaprint.a" -path "*Release*" | head -1)
    SIM_LIB=$(find "$CHROMAPRINT_SRC/build-ios-sim" -name "libchromaprint.a" -path "*Release*" | head -1)

    if [ -z "$DEVICE_LIB" ] || [ -z "$SIM_LIB" ]; then
        echo "错误: 未找到编译产物"
        echo "Device: $DEVICE_LIB"
        echo "Simulator: $SIM_LIB"
        exit 1
    fi

    # 头文件
    HEADERS_DIR="$IOS_OUTPUT/headers"
    mkdir -p "$HEADERS_DIR"
    cp "$CHROMAPRINT_SRC/src/chromaprint.h" "$HEADERS_DIR/"

    # xcframework
    rm -rf "$IOS_OUTPUT/Chromaprint.xcframework"
    xcodebuild -create-xcframework \
        -library "$DEVICE_LIB" -headers "$HEADERS_DIR" \
        -library "$SIM_LIB" -headers "$HEADERS_DIR" \
        -output "$IOS_OUTPUT/Chromaprint.xcframework"

    echo "✓ iOS xcframework 创建完成: $IOS_OUTPUT/Chromaprint.xcframework"
    echo ""
}

# 安装 iOS 库到项目
install_ios() {
    echo "=== 安装 iOS 库到项目 ==="

    local IOS_OUTPUT="$OUTPUT_DIR/ios"
    local IOS_FRAMEWORKS="$PROJECT_ROOT/ios/Frameworks"

    if [ ! -d "$IOS_OUTPUT/Chromaprint.xcframework" ]; then
        echo "错误: xcframework 不存在，请先编译"
        exit 1
    fi

    mkdir -p "$IOS_FRAMEWORKS"
    rm -rf "$IOS_FRAMEWORKS/Chromaprint.xcframework"
    cp -R "$IOS_OUTPUT/Chromaprint.xcframework" "$IOS_FRAMEWORKS/"

    echo "✓ 已安装到: $IOS_FRAMEWORKS/Chromaprint.xcframework"
    echo ""
    echo "请在 Xcode 中:"
    echo "1. 打开 ios/Runner.xcworkspace"
    echo "2. 选择 Runner target -> Build Phases"
    echo "3. 在 Link Binary With Libraries 中添加 Chromaprint.xcframework"
    echo "4. 在 Build Settings -> Swift Compiler - Custom Flags 添加: -DCHROMAPRINT_AVAILABLE"
    echo ""
}

# 下载 Android 预编译库
download_android() {
    echo "=== 下载 Android 预编译库 ==="

    local ANDROID_OUTPUT="$OUTPUT_DIR/android"
    mkdir -p "$ANDROID_OUTPUT"

    # 尝试从几个可能的源下载
    echo "尝试下载预编译的 Android 库..."

    # 方案1: 从 AcoustID 官方 (如果有)
    # 方案2: 从第三方 GitHub 仓库

    local PREBUILT_URL="https://github.com/niclas3640/chromaprint-android/releases/download/v1.5.1/chromaprint-android-v1.5.1.zip"
    local ARCHIVE="$BUILD_DIR/chromaprint-android.zip"

    if [ ! -f "$ARCHIVE" ]; then
        echo "下载: $PREBUILT_URL"
        if curl -L -o "$ARCHIVE" "$PREBUILT_URL" 2>/dev/null; then
            echo "✓ 下载成功"
        else
            echo "⚠ 预编译库下载失败"
            echo ""
            echo "需要手动编译 Android 库:"
            echo "1. 安装 Android NDK"
            echo "2. 运行 ./build_all.sh android-compile"
            echo ""
            echo "或者使用替代方案:"
            echo "- 移动端仅使用元数据搜索 (已自动回退)"
            echo "- 服务端处理音频指纹"
            return 1
        fi
    fi

    # 解压
    echo "解压..."
    unzip -o "$ARCHIVE" -d "$ANDROID_OUTPUT"

    echo "✓ Android 库下载完成"
    echo ""
}

# 安装 Android 库到项目
install_android() {
    echo "=== 安装 Android 库到项目 ==="

    local ANDROID_OUTPUT="$OUTPUT_DIR/android"
    local JNILIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"

    # 查找 .so 文件
    local SO_FILES=$(find "$ANDROID_OUTPUT" -name "libchromaprint.so" 2>/dev/null)

    if [ -z "$SO_FILES" ]; then
        echo "错误: 未找到 Android 库文件"
        exit 1
    fi

    mkdir -p "$JNILIBS/arm64-v8a"
    mkdir -p "$JNILIBS/armeabi-v7a"
    mkdir -p "$JNILIBS/x86_64"

    # 复制文件 (根据实际目录结构调整)
    for arch in arm64-v8a armeabi-v7a x86_64; do
        local so_file=$(find "$ANDROID_OUTPUT" -path "*$arch*" -name "libchromaprint.so" | head -1)
        if [ -n "$so_file" ]; then
            cp "$so_file" "$JNILIBS/$arch/"
            echo "✓ 已安装 $arch"
        fi
    done

    echo ""
    echo "请在 android/app/build.gradle 中添加:"
    echo ""
    echo "android {"
    echo "    externalNativeBuild {"
    echo "        cmake {"
    echo "            path \"src/main/cpp/CMakeLists.txt\""
    echo "        }"
    echo "    }"
    echo "}"
    echo ""
}

# 从源码编译 Android (需要 NDK)
build_android_from_source() {
    echo "=== 从源码编译 Android ==="

    # 检查 NDK
    if [ -z "$ANDROID_NDK_HOME" ]; then
        if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
            ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/$(ls $HOME/Library/Android/sdk/ndk | tail -1)"
        else
            echo "错误: 未找到 Android NDK"
            echo "请设置 ANDROID_NDK_HOME 环境变量"
            exit 1
        fi
    fi

    echo "使用 NDK: $ANDROID_NDK_HOME"

    local ANDROID_OUTPUT="$OUTPUT_DIR/android"
    mkdir -p "$ANDROID_OUTPUT"

    for ABI in arm64-v8a armeabi-v7a x86_64; do
        echo "编译 $ABI..."

        local BUILD_PATH="$CHROMAPRINT_SRC/build-android-$ABI"
        rm -rf "$BUILD_PATH"
        mkdir -p "$BUILD_PATH"
        cd "$BUILD_PATH"

        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
            -DANDROID_ABI=$ABI \
            -DANDROID_PLATFORM=android-21 \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
            -DBUILD_SHARED_LIBS=ON \
            -DBUILD_TOOLS=OFF \
            -DBUILD_TESTS=OFF \
            -DFFT_LIB=kissfft \
            -DKISSFFT_SOURCE_DIR="$KISSFFT_SRC" \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5

        cmake --build . --config Release

        # CMake 的产物位于 src/ 子目录；不要假设它在构建根目录。
        local CHROMAPRINT_LIB
        CHROMAPRINT_LIB=$(find "$BUILD_PATH" -type f -name "libchromaprint.so" -print -quit)
        if [ -z "$CHROMAPRINT_LIB" ]; then
            echo "错误: 未找到 $ABI 的 libchromaprint.so"
            exit 1
        fi

        # 复制产物
        mkdir -p "$ANDROID_OUTPUT/$ABI"
        cp "$CHROMAPRINT_LIB" "$ANDROID_OUTPUT/$ABI/"
    done

    echo "✓ Android 编译完成"
    echo ""
}

# 主流程
main() {
    local cmd="${1:-all}"

    check_dependencies

    case "$cmd" in
        ios)
            download_sources
            build_ios
            install_ios
            ;;
        android)
            download_android || true
            install_android
            ;;
        android-compile)
            download_sources
            build_android_from_source
            install_android
            ;;
        install)
            install_ios
            install_android
            ;;
        all)
            download_sources
            build_ios
            install_ios
            download_android || true
            install_android || true
            ;;
        *)
            echo "用法: $0 [ios|android|android-compile|install|all]"
            echo ""
            echo "  ios            - 编译并安装 iOS 库"
            echo "  android        - 下载并安装 Android 预编译库"
            echo "  android-compile- 从源码编译 Android (需要 NDK)"
            echo "  install        - 仅安装已编译的库"
            echo "  all            - 执行所有步骤"
            exit 1
            ;;
    esac

    echo "========================================"
    echo "  完成!"
    echo "========================================"
}

main "$@"
