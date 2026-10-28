cmake_minimum_required(VERSION 3.16)
project(seven VERSION 1.4.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)

# ---- Find LLVM ----
find_package(LLVM REQUIRED CONFIG)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "LLVM include dirs: ${LLVM_INCLUDE_DIRS}")

include_directories(${LLVM_INCLUDE_DIRS} ${CMAKE_SOURCE_DIR}/src)
add_definitions(${LLVM_DEFINITIONS})

# ---- LLVM Compiler (seven-llvm) ----
add_executable(seven-llvm
    src/llvm_main.c
    src/llvm_lexer.c
    src/llvm_codegen.c
)

llvm_map_components_to_libnames(LLVM_LIBS
    core analysis native bitwriter
)

target_link_libraries(seven-llvm ${LLVM_LIBS})

if(NOT WIN32)
    target_link_libraries(seven-llvm m)
endif()

# ---- Runtime object (compiled separately for linking with user programs) ----
add_library(seven_runtime OBJECT src/llvm_runtime.c)

# ---- Install ----
install(TARGETS seven-llvm RUNTIME DESTINATION bin)

# Copy runtime .o next to the binary so it can find it at link time
add_custom_command(TARGET seven-llvm POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_OBJECTS:seven_runtime>
        $<TARGET_FILE_DIR:seven-llvm>/seven_runtime.o
    COMMENT "Copying runtime object next to seven-llvm"
)

# ---- Info ----
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C compiler: ${CMAKE_C_COMPILER}")
