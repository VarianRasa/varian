set(LIBREOFFICE_RUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libreoffice/runtime")

if(EXISTS "${LIBREOFFICE_RUNTIME_DIR}/program/soffice.exe")
  install(DIRECTORY "${LIBREOFFICE_RUNTIME_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/libreoffice"
    COMPONENT Runtime)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR
    "LibreOffice runtime is not staged. Run tool/package_libreoffice_windows.ps1 with LIBREOFFICE_ARCHIVE and LIBREOFFICE_SHA256.")
else()
  message(STATUS "LibreOffice runtime not staged; document conversion is unavailable in this development build.")
endif()
