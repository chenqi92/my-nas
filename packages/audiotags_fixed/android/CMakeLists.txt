cmake_minimum_required(VERSION 3.10)

# Download the binaries from GitHub.
set(Version "1.4.5")
set(LibPath "${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs")
set(ArchivePath "${CMAKE_CURRENT_SOURCE_DIR}/android.tar.gz")

if(NOT EXISTS "${LibPath}/arm64-v8a/libaudiotags.so" OR
   NOT EXISTS "${LibPath}/armeabi-v7a/libaudiotags.so" OR
   NOT EXISTS "${LibPath}/x86_64/libaudiotags.so")
  if(NOT EXISTS ${ArchivePath})
    file(DOWNLOAD
      "https://github.com/erikas-taroza/audiotags/releases/download/v${Version}/android.tar.gz"
      ${ArchivePath}
      TLS_VERIFY ON
    )
  endif()
  file(MAKE_DIRECTORY ${LibPath})
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E tar -xzf ${ArchivePath}
    WORKING_DIRECTORY ${LibPath}
  )
endif()
