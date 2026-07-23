cmake_minimum_required(VERSION 3.0.0)
project(utslack C CXX)

set(CMAKE_AUTOMOC ON)

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

configure_file(manifest.json.in ${CMAKE_CURRENT_BINARY_DIR}/manifest.json)
configure_file(${DESKTOP_FILE_NAME}.in ${CMAKE_CURRENT_BINARY_DIR}/${DESKTOP_FILE_NAME})

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${PROJECT_NAME}.apparmor DESTINATION ${DATA_DIR})
install(FILES ${PROJECT_NAME}-contenthub.json DESTINATION ${DATA_DIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${DESKTOP_FILE_NAME} DESTINATION ${DATA_DIR})
install(DIRECTORY assets DESTINATION ${DATA_DIR})
install(DIRECTORY qml DESTINATION ${DATA_DIR})
install(FILES push/push-helper.json push/push-apparmor.json DESTINATION push)
install(PROGRAMS push/pushexec DESTINATION push)
