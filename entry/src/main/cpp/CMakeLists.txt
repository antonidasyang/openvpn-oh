# Native build for the OpenVPN HarmonyOS NEXT client.
#
# Produces libovpnclient.so, exposed to ArkTS via NAPI. Wraps the openvpn3
# ClientAPI (subclass OpenVPNClient) and bridges its TunBuilder / SocketProtect
# callbacks to the HarmonyOS VpnExtensionAbility through threadsafe JS calls.
#
# Dependencies expected under third_party/ (see scripts/fetch-third-party.sh):
#   third_party/openvpn3/                 (AGPLv3 — github.com/OpenVPN/openvpn3)
#   third_party/asio/asio/include/        (Boost Software License)
#   third_party/mbedtls/                  (Apache 2.0)
#   third_party/lz4/                      (BSD-2)

cmake_minimum_required(VERSION 3.16)
project(ovpnclient)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# The OHOS NDK toolchain file always passes `--gcc-toolchain=...` to clang,
# but clang has no use for it (the NDK is a pure-clang toolchain) and emits
# `-Wunused-command-line-argument`. mbedtls and other vendored libs build
# with `-Werror`, so the warning becomes a fatal error on every TU.
# Suppress it project-wide before any add_subdirectory() so it propagates to
# all targets defined below.
add_compile_options(-Wno-unused-command-line-argument)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(THIRD_PARTY ${NATIVERENDER_ROOT_PATH}/third_party)

set(OVPN3   ${THIRD_PARTY}/openvpn3)
set(ASIO    ${THIRD_PARTY}/asio/asio/include)
set(MBEDTLS ${THIRD_PARTY}/mbedtls)
set(LZ4     ${THIRD_PARTY}/lz4/lib)

if (NOT EXISTS ${OVPN3}/client/ovpncli.cpp)
    message(FATAL_ERROR
        "openvpn3 sources are missing under entry/src/main/cpp/third_party/openvpn3.\n"
        "Run scripts/fetch-third-party.sh from the project root first.")
endif()

# ----- mbedTLS (static) -----
set(ENABLE_PROGRAMS  OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING   OFF CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON  CACHE BOOL "" FORCE)
# Belt-and-braces: also tell mbedtls itself to not promote warnings to errors.
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
add_subdirectory(${MBEDTLS} mbedtls_build EXCLUDE_FROM_ALL)

# ----- lz4 (single source file, static) -----
add_library(lz4_static STATIC ${LZ4}/lz4.c)
target_include_directories(lz4_static PUBLIC ${LZ4})

# ----- openvpn3 ClientAPI -----
# openvpn3 ships a single translation unit (ovpncli.cpp) that pulls in the rest
# of the library via header-only includes. We compile it into our shared lib.
add_library(ovpncli_obj OBJECT ${OVPN3}/client/ovpncli.cpp)
target_include_directories(ovpncli_obj PRIVATE
    ${OVPN3}
    ${ASIO}
    ${MBEDTLS}/include
    ${LZ4}
)
target_compile_definitions(ovpncli_obj PRIVATE
    USE_MBEDTLS
    USE_ASIO
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
    HAVE_LZ4
    # openvpn3's openvpn/common/platform.hpp auto-defines OPENVPN_PLATFORM_LINUX
    # when __linux__ is set (true for the OHOS NDK target). We add only the
    # OHOS-specific flag here; doubling up triggers -Wmacro-redefined.
    OPENVPN_PLATFORM_OHOS
    # Drive the tun via our TunBuilderBase overrides (tun_builder_* ->
    # VpnConnection). NOTE: do NOT define OPENVPN_FORCE_TUN_NULL here — ovpncli
    # gates it with `#if defined(...)`, so even `=0` forces the null tun (the
    # tunnel connects but no real interface/IP is ever created).
    USE_TUN_BUILDER
    OPENVPN_LOG_LOGBASE_H
)
target_compile_options(ovpncli_obj PRIVATE
    -Wno-deprecated-declarations
    -Wno-unused-parameter
    -Wno-unused-variable
    -Wno-error
)

# ----- The shared lib we ship -----
add_library(ovpnclient SHARED
    napi_init.cpp
    ovpn_client.cpp
    async_bridge.cpp
    $<TARGET_OBJECTS:ovpncli_obj>
)

target_include_directories(ovpnclient PRIVATE
    ${NATIVERENDER_ROOT_PATH}
    ${OVPN3}
    ${ASIO}
    ${MBEDTLS}/include
    ${LZ4}
)

target_compile_definitions(ovpnclient PRIVATE
    USE_MBEDTLS
    USE_ASIO
    ASIO_STANDALONE
    HAVE_LZ4
    # See note above re: OPENVPN_PLATFORM_LINUX.
    OPENVPN_PLATFORM_OHOS
    # Keep tun-builder headers consistent with ovpncli_obj (ovpn_client.cpp
    # overrides TunBuilderBase).
    USE_TUN_BUILDER
)

target_link_libraries(ovpnclient PRIVATE
    libace_napi.z.so
    libhilog_ndk.z.so
    libuv.so
    mbedtls
    mbedx509
    mbedcrypto
    lz4_static
)
