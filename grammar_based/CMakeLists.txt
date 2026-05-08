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
target_compile_definitions(das_fuzz PRIVATE
    DAS_FUZZ_DAS_ROOT="${PROJECT_SOURCE_DIR}/modules/daScript")

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

# Generate fuzzing seeds + trees into /dev/shm via grammar_generator-type.
set(DAS_FUZZ_SEED_COUNT 1000 CACHE STRING "Number of seeds to generate")
set(DAS_FUZZ_SEED_MAX_SIZE 200 CACHE STRING "Max seed size")
set(DAS_FUZZ_SEED_DIR /dev/shm/das_fuzz_seeds CACHE PATH "Seed output dir")
set(DAS_FUZZ_TREES_DIR /dev/shm/das_fuzz_trees CACHE PATH "Tree output dir")

set(GRAMMAR_MUTATOR_DIR ${PROJECT_SOURCE_DIR}/modules/Grammar-Mutator)

# Rebuild grammar: regenerate JSON from Bison .ypp via convert.py,
# then rebuild grammar_generator-type and libgrammarmutator-type.so.
set(DAS_FUZZ_BISON_YPP
    ${PROJECT_SOURCE_DIR}/modules/daScript/src/parser/ds2_parser.ypp
    CACHE FILEPATH "Bison grammar source for convert.py")
set(DAS_FUZZ_GRAMMAR_JSON
    ${PROJECT_SOURCE_DIR}/type_inference_simple.json
    CACHE FILEPATH "Generated grammar JSON for Grammar-Mutator")

find_package(Python3 COMPONENTS Interpreter)
if(NOT Python3_Interpreter_FOUND)
    set(Python3_EXECUTABLE python3)
endif()

add_custom_target(rebuild_grammar
    COMMAND sh -c
        "${Python3_EXECUTABLE} ${PROJECT_SOURCE_DIR}/convert.py ${DAS_FUZZ_BISON_YPP} > ${DAS_FUZZ_GRAMMAR_JSON}"
    COMMAND make -C ${GRAMMAR_MUTATOR_DIR} clean
    COMMAND make -C ${GRAMMAR_MUTATOR_DIR}
        GRAMMAR_FILE=${DAS_FUZZ_GRAMMAR_JSON}
    COMMENT "Rebuilding grammar from ${DAS_FUZZ_BISON_YPP}"
    USES_TERMINAL
)
add_custom_target(gen_seeds
    COMMAND ${CMAKE_COMMAND} -E rm -rf
        ${DAS_FUZZ_SEED_DIR} ${DAS_FUZZ_TREES_DIR}
    COMMAND ${CMAKE_COMMAND} -E make_directory
        ${DAS_FUZZ_SEED_DIR} ${DAS_FUZZ_TREES_DIR}
    COMMAND ${CMAKE_COMMAND} -E env
        LD_LIBRARY_PATH=${GRAMMAR_MUTATOR_DIR}
        ${GRAMMAR_MUTATOR_DIR}/grammar_generator-type
        ${DAS_FUZZ_SEED_COUNT} ${DAS_FUZZ_SEED_MAX_SIZE}
        ${DAS_FUZZ_SEED_DIR} ${DAS_FUZZ_TREES_DIR}
    COMMENT "Generating ${DAS_FUZZ_SEED_COUNT} seeds in ${DAS_FUZZ_SEED_DIR}"
    VERBATIM
    USES_TERMINAL
)
