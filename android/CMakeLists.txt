cmake_minimum_required(VERSION 3.9.0)

add_library(webrtc
            SHARED
            ../cpp/TypedArrayApi.cpp
            ./cpp-adapter.cpp
            $ENV{ROOT_DIR}/node_modules/react-native/ReactCommon/jsi/jsi/jsi.cpp
)

include_directories(
            $ENV{ROOT_DIR}/node_modules/react-native/React
            $ENV{ROOT_DIR}/node_modules/react-native/React/Base
            $ENV{ROOT_DIR}/node_modules/react-native/ReactCommon/jsi
            ../cpp
)

set_target_properties(
        webrtc PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        POSITION_INDEPENDENT_CODE ON
)

target_link_libraries(
        webrtc
        android
)
