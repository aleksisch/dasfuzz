cmake_minimum_required (VERSION 3.16)
project (das-fuzz)

add_subdirectory(modules/daScript)

add_executable(das_fuzz main.cpp)
target_link_libraries(das_fuzz PRIVATE libDaScript libDasModuleUnitTest)
target_include_directories(das_fuzz
    PUBLIC ${PROJECT_SOURCE_DIR}/modules/daScript/include
    PRIVATE ${PROJECT_SOURCE_DIR}/modules/daScript/modules/dasUnitTest
)
target_compile_options(das_fuzz PRIVATE -fno-rtti)
