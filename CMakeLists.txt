cmake_minimum_required(VERSION 3.14)
project(GPU_Simulator VERSION 1.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Options
option(BUILD_TESTS "Build tests" ON)
option(BUILD_DOCS "Build documentation" OFF)
option(ENABLE_WARNINGS "Enable warnings" ON)
option(ENABLE_DPI "Enable DPI-C interface" ON)

# Set compiler flags
if(ENABLE_WARNINGS)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic")
    elseif(MSVC)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4")
    endif()
endif()

# Create shared library for DPI
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Define source directories
set(SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(RTL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/rtl)
set(TB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tb)

# Find all source files
file(GLOB_RECURSE SRC_FILES 
    ${SRC_DIR}/*.cpp
)

# Define include directories
include_directories(${INCLUDE_DIR})

# Create the DPI library
add_library(gpusim SHARED ${SRC_FILES})
set_target_properties(gpusim PROPERTIES
    OUTPUT_NAME "gpusim"
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

# Add custom target for RTL simulation
find_program(VCS_EXECUTABLE vcs)
if(VCS_EXECUTABLE)
    file(GLOB_RECURSE RTL_FILES ${RTL_DIR}/*.sv)
    file(GLOB_RECURSE TB_FILES ${TB_DIR}/*.sv)
    
    add_custom_target(compile_rtl
        COMMAND ${VCS_EXECUTABLE} -sverilog -timescale=1ns/1ps -full64 -debug_access+all 
                -LDFLAGS "-L${CMAKE_BINARY_DIR}/lib -lgpusim"
                -o ${CMAKE_BINARY_DIR}/bin/gpu_simulator
                ${RTL_FILES} ${TB_FILES}
        DEPENDS gpusim
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "Compiling RTL with VCS"
    )
else()
    message(WARNING "VCS not found. RTL compilation target not available.")
endif()

# Add custom target for running simulation
add_custom_target(run_sim
    COMMAND ${CMAKE_BINARY_DIR}/bin/gpu_simulator -l ${CMAKE_BINARY_DIR}/sim.log
    DEPENDS compile_rtl
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Running GPU simulator"
)

# Build tests if enabled
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Generate documentation if enabled
if(BUILD_DOCS)
    find_package(Doxygen)
    if(DOXYGEN_FOUND)
        set(DOXYGEN_IN ${CMAKE_CURRENT_SOURCE_DIR}/docs/Doxyfile.in)
        set(DOXYGEN_OUT ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile)
        
        configure_file(${DOXYGEN_IN} ${DOXYGEN_OUT} @ONLY)
        
        add_custom_target(docs
            COMMAND ${DOXYGEN_EXECUTABLE} ${DOXYGEN_OUT}
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            COMMENT "Generating documentation with Doxygen"
            VERBATIM
        )
    else()
        message(WARNING "Doxygen not found. Documentation will not be generated.")
    endif()
endif()

# Installation rules
install(TARGETS gpusim
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY ${INCLUDE_DIR}/
    DESTINATION include
    FILES_MATCHING PATTERN "*.h"
)

# Summary
message(STATUS "Configuration Summary:")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  Build Tests: ${BUILD_TESTS}")
message(STATUS "  Build Documentation: ${BUILD_DOCS}")
message(STATUS "  Enable Warnings: ${ENABLE_WARNINGS}")
message(STATUS "  Enable DPI: ${ENABLE_DPI}")