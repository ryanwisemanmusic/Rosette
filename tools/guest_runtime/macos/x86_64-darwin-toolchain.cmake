# Rosette-owned target contract for building the clean Xenia checkout as an
# x86_64 Mach-O image on Apple Silicon.  The source checkout must not infer
# its backend from the architecture of the Rosette host process.

set(CMAKE_SYSTEM_NAME Darwin CACHE STRING "" FORCE)
set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "" FORCE)
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0 CACHE STRING "" FORCE)

set(CMAKE_C_COMPILER /usr/bin/clang CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER /usr/bin/clang++ CACHE FILEPATH "" FORCE)
set(CMAKE_OBJCXX_COMPILER /usr/bin/clang++ CACHE FILEPATH "" FORCE)

# CMake's compiler probes must produce target objects without trying to run
# them through the native ARM64 process.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
