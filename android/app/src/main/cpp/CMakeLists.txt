cmake_minimum_required(VERSION 3.22.1)

project(byedpi_native)

# Path to byedpi sources in the vendored ByeByeDPI directory
set(BYEDPI_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ByeByeDPI/app/src/main/cpp/byedpi)

file(GLOB BYE_DPI_SRC ${BYEDPI_SRC_DIR}/*.c)
list(REMOVE_ITEM BYE_DPI_SRC ${BYEDPI_SRC_DIR}/win_service.c)

add_library(byedpi SHARED ${BYE_DPI_SRC} native-lib.c)
target_include_directories(byedpi PRIVATE ${BYEDPI_SRC_DIR})

target_compile_options(byedpi PRIVATE -std=c99 -O2 -Wall -Wno-unused -Wextra -Wno-unused-parameter -pedantic)
target_compile_definitions(byedpi PRIVATE ANDROID_APP)

target_link_libraries(byedpi PRIVATE android log)
