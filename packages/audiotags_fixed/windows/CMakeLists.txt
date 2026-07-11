# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "audiotags")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "audiotags_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "audiotags_plugin.cpp"
  "audiotags_plugin.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/audiotags/audiotags_plugin_c_api.h"
  "audiotags_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Download the binary from GitHub.
# 解压到 build（binary）目录，而不是 source 目录：Flutter 通过 ephemeral
# .plugin_symlinks/audiotags 软链引用 source 目录，新版 CMake 的 `cmake -E tar`
# (libarchive SECURE_SYMLINKS) 会拒绝穿过软链解压。CMAKE_CURRENT_BINARY_DIR
# 是 build/ 下的真实路径。
set(Version "1.4.5")
set(LibPath "${CMAKE_CURRENT_BINARY_DIR}/windows.tar.gz")
if(NOT EXISTS "${LibPath}")
  file(DOWNLOAD
    "https://github.com/erikas-taroza/audiotags/releases/download/v${Version}/windows.tar.gz"
    "${LibPath}"
    TLS_VERIFY ON
  )
endif()

if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/audiotags.dll")
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E tar -xzf "${LibPath}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    RESULT_VARIABLE audiotags_extract_result
  )
  if(NOT audiotags_extract_result EQUAL 0)
    message(FATAL_ERROR "audiotags: failed to extract ${LibPath} (result ${audiotags_extract_result})")
  endif()
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(audiotags_bundled_libraries
  "${CMAKE_CURRENT_BINARY_DIR}/audiotags.dll"
  PARENT_SCOPE
)
