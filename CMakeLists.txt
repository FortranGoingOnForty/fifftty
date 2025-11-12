cmake_minimum_required(VERSION 3.20)

# Force gfortran as Fortran compiler
set(CMAKE_Fortran_COMPILER "gfortran")

project(fortty LANGUAGES Fortran C)

# Fortran compiler flags (GCC/gfortran specific)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Wall -Wextra -std=f2018")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g -O0 -fcheck=all -fbacktrace")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O3 -march=native")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Flang|LLVMFlang")
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Wall -std=f2018")
    set(CMAKE_Fortran_FLAGS_DEBUG "-g -O0")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O3 -march=native")
else()
    message(WARNING "Untested Fortran compiler: ${CMAKE_Fortran_COMPILER_ID}")
endif()

# Use pkg-config to find dependencies
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED gtk4)
pkg_check_modules(FREETYPE REQUIRED freetype2)

# Find OpenGL
find_package(OpenGL REQUIRED)

# Include directories
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${GTK4_INCLUDE_DIRS}
    ${FREETYPE_INCLUDE_DIRS}
    ${OPENGL_INCLUDE_DIR}
)

# Link directories
link_directories(
    ${GTK4_LIBRARY_DIRS}
    ${FREETYPE_LIBRARY_DIRS}
)

# Core library sources (can be tested independently)
set(FORTTY_LIB_SOURCES
    src/terminal_grid.f90
    src/pty_manager.f90
    src/vt_parser.f90
)

# Application sources (depend on core library)
set(FORTTY_APP_SOURCES
    src/opengl_bindings.f90
    src/freetype_bindings.f90
    src/font_manager.f90
    src/renderer.f90
    src/gtk_bindings.f90
    src/fortty_app.f90
    src/main.f90
)

# Create core library for testing
add_library(fortty_core STATIC ${FORTTY_LIB_SOURCES})

# Main executable
add_executable(fortty ${FORTTY_APP_SOURCES})

# Link libraries
target_link_libraries(fortty
    fortty_core
    ${GTK4_LIBRARIES}
    ${FREETYPE_LIBRARIES}
    ${OPENGL_LIBRARIES}
)

# Compiler definitions from GTK4
add_definitions(${GTK4_CFLAGS_OTHER})

# Enable testing
enable_testing()

# Test sources
set(TEST_SOURCES
    tests/test_framework.f90
    tests/test_vt_parser.f90
)

# Test executable
add_executable(test_vt_parser ${TEST_SOURCES})
target_link_libraries(test_vt_parser fortty_core)

# Add test to CTest
add_test(NAME vt_parser_tests COMMAND test_vt_parser)

# Install target
install(TARGETS fortty DESTINATION bin)
