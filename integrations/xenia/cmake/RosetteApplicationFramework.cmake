# Optional Rosette application-framework integration for Xenia.
#
# Usage from Xenia's top-level CMakeLists.txt:
#   option(XENIA_ENABLE_ROSETTE_APPLICATION_FRAMEWORK "..." OFF)
#   if(XENIA_ENABLE_ROSETTE_APPLICATION_FRAMEWORK)
#     include("${ROSETTE_FRAMEWORK_ROOT}/integrations/xenia/cmake/RosetteApplicationFramework.cmake")
#     rosette_enable_application_framework()
#   endif()
#
# The default is deliberately opt-in.  The bridge resolves exported Rosette
# symbols with dlsym, so normal Xenia builds have no link dependency and keep
# their existing behavior.

function(rosette_enable_application_framework)
  if(NOT DEFINED ROSETTE_FRAMEWORK_ROOT OR
     NOT EXISTS "${ROSETTE_FRAMEWORK_ROOT}/integrations/xenia/include/rosette_xenia_application_bridge.h")
    message(FATAL_ERROR
      "ROSETTE_FRAMEWORK_ROOT must point at a Rosette checkout containing "
      "integrations/xenia/include/rosette_xenia_application_bridge.h")
  endif()

  include_directories(BEFORE
    "${ROSETTE_FRAMEWORK_ROOT}/include"
    "${ROSETTE_FRAMEWORK_ROOT}/integrations/xenia/include")
  add_compile_definitions(XE_ENABLE_ROSETTE_APPLICATION_FRAMEWORK=1)
  message(STATUS "Rosette application framework adapter enabled: ${ROSETTE_FRAMEWORK_ROOT}")
endfunction()
