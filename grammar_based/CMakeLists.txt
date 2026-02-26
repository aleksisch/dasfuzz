cmake_minimum_required (VERSION 3.16)
project (das-fuzz)

# This is mandatory until libDaScript not export it's flags.
SET(CMAKE_CXX_FLAGS_RELEASE "-O3 -fno-rtti -fomit-frame-pointer -fno-stack-protector -s -DDAS_FUSION=2 -DDAS_DEBUGGER=0 -DNDEBUG=1")
add_subdirectory(modules/daScript)

add_executable(das_fuzz main.cpp)
target_link_libraries(das_fuzz PRIVATE libDaScript)
target_include_directories(das_fuzz
    PUBLIC ${PROJECT_SOURCE_DIR}/modules/daScript/include
)
