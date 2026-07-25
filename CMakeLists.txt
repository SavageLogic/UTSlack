cmake_minimum_required(VERSION 3.0.0)
project(utslack C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

execute_process(
    COMMAND dpkg-architecture -qDEB_HOST_MULTIARCH
    OUTPUT_VARIABLE ARCH_TRIPLET
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)

set(PROJECT_NAME "utslack")
set(FULL_PROJECT_NAME "utslack.savagelogic")
set(DATA_DIR /)
set(DESKTOP_FILE_NAME ${PROJECT_NAME}.desktop)
set(QT_IMPORTS_DIR lib/${ARCH_TRIPLET})

find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick Network)

configure_file(manifest.json.in ${CMAKE_CURRENT_BINARY_DIR}/manifest.json)
configure_file(${DESKTOP_FILE_NAME}.in ${CMAKE_CURRENT_BINARY_DIR}/${DESKTOP_FILE_NAME})

# QML plugin (MediaCache) — app itself still launches via qmlscene
add_library(utslackplugin SHARED
    src/plugin.cpp
    src/mediacache.cpp
    src/mediacache.h
)

target_link_libraries(utslackplugin
    Qt5::Core
    Qt5::Gui
    Qt5::Qml
    Qt5::Quick
    Qt5::Network
)

set_target_properties(utslackplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/UTSlack
)

# qmldir next to the .so
configure_file(src/qmldir ${CMAKE_CURRENT_BINARY_DIR}/UTSlack/qmldir COPYONLY)

install(TARGETS utslackplugin LIBRARY DESTINATION ${QT_IMPORTS_DIR}/UTSlack)
install(FILES src/qmldir DESTINATION ${QT_IMPORTS_DIR}/UTSlack)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${PROJECT_NAME}.apparmor DESTINATION ${DATA_DIR})
install(FILES ${PROJECT_NAME}-contenthub.json DESTINATION ${DATA_DIR})
install(FILES ${PROJECT_NAME}.url-dispatcher DESTINATION ${DATA_DIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${DESKTOP_FILE_NAME} DESTINATION ${DATA_DIR})
install(DIRECTORY assets DESTINATION ${DATA_DIR})
install(DIRECTORY qml DESTINATION ${DATA_DIR})
install(FILES push/push-helper.json push/push-apparmor.json DESTINATION push)
install(PROGRAMS push/pushexec DESTINATION push)
