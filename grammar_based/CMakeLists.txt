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

# Optional in-process AOT C++ syntax check via libclang. Loaded once per
# AFL fuzz worker; a precompiled-header preamble keeps per-input cost down.
find_library(LIBCLANG NAMES clang clang-20 clang-19 clang-18 clang-17 clang-16)
find_path(LIBCLANG_INCLUDE clang-c/Index.h
    PATHS /usr/lib/llvm-20/include /usr/lib/llvm-19/include
          /usr/lib/llvm-18/include /usr/lib/llvm-17/include
          /usr/lib/llvm-16/include /usr/include)
if(LIBCLANG AND LIBCLANG_INCLUDE)
    message(STATUS "libclang: ${LIBCLANG} (include: ${LIBCLANG_INCLUDE})")
    target_link_libraries(das_fuzz PRIVATE ${LIBCLANG})
    target_include_directories(das_fuzz PRIVATE ${LIBCLANG_INCLUDE})
    target_compile_definitions(das_fuzz PRIVATE
        DAS_FUZZ_AOT_CHECK
        DAS_FUZZ_DAS_INCLUDE="${PROJECT_SOURCE_DIR}/modules/daScript/include"
        DAS_FUZZ_FMT_INCLUDE="${PROJECT_SOURCE_DIR}/modules/daScript/3rdparty/fmt/include"
        DAS_FUZZ_UNITTEST_INCLUDE="${PROJECT_SOURCE_DIR}/modules/daScript/modules/dasUnitTest"
    )
else()
    message(STATUS "libclang not found — AOT C++ syntax check disabled")
endif()
