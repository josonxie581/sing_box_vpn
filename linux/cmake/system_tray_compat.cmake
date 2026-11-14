# system_tray 2.0.3 selects Ayatana headers but still dlopens the legacy library.
# Compile a corrected copy in this build tree; never edit the shared pub cache.
get_target_property(TRAY_SOURCE_DIR system_tray_plugin SOURCE_DIR)
get_target_property(TRAY_SOURCES system_tray_plugin SOURCES)
list(FIND TRAY_SOURCES "tray.cc" TRAY_SOURCE_INDEX)
if(TRAY_SOURCE_INDEX EQUAL -1)
  message(FATAL_ERROR "Review the system_tray compatibility patch after upgrading the plugin.")
endif()
set(TRAY_ORIGINAL "${TRAY_SOURCE_DIR}/tray.cc")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${TRAY_ORIGINAL}")
file(READ "${TRAY_ORIGINAL}" TRAY_CONTENT)
set(TRAY_OLD_LOADER "    void* handle = dlopen(\"libappindicator3.so.1\", RTLD_LAZY);")
string(FIND "${TRAY_CONTENT}" "${TRAY_OLD_LOADER}" TRAY_LOADER_INDEX)
if(TRAY_LOADER_INDEX EQUAL -1)
  message(FATAL_ERROR "system_tray loader changed; review or remove the compatibility patch.")
endif()
set(TRAY_NEW_LOADER "#ifdef HAVE_AYATANA
    void* handle = dlopen(\"libayatana-appindicator3.so.1\", RTLD_LAZY);
#else
${TRAY_OLD_LOADER}
#endif")
string(REPLACE "${TRAY_OLD_LOADER}" "${TRAY_NEW_LOADER}" TRAY_CONTENT "${TRAY_CONTENT}")
set(TRAY_PATCHED "${CMAKE_CURRENT_BINARY_DIR}/system_tray_compat/tray.cc")
file(WRITE "${TRAY_PATCHED}" "${TRAY_CONTENT}")
list(REMOVE_AT TRAY_SOURCES ${TRAY_SOURCE_INDEX})
list(APPEND TRAY_SOURCES "${TRAY_PATCHED}")
set_property(TARGET system_tray_plugin PROPERTY SOURCES "${TRAY_SOURCES}")
target_include_directories(system_tray_plugin PRIVATE "${TRAY_SOURCE_DIR}")
