# Official CEF "Standard Distribution" from the Spotify automated builds CDN
# (https://cef-builds.spotifycdn.com). All platforms are kept on the same
# CEF/Chromium version. To bump CEF, change CEF_VERSION below.
set(CEF_CDN "https://cef-builds.spotifycdn.com")
set(CEF_VERSION "149.0.6+g0d0eeb6+chromium-149.0.7827.201")

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(WARNING "current system is Linux")
        if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR
           CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64" OR
           CMAKE_CXX_COMPILER_TARGET MATCHES "aarch64" OR
           CMAKE_CXX_COMPILER_TARGET MATCHES "arm64")
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_linuxarm64.tar.bz2")
    else()
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_linux64.tar.bz2")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    message(WARNING "current system is Windows")
    # Use the official CEF standard distribution and build libcef_dll_wrapper
    # from source (see windows/CMakeLists.txt), the same way Linux does.
    set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_windows64.tar.bz2")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    message(WARNING "current system is macOS")
    if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "arm64")
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_macosarm64.tar.bz2")
    else()
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_macosx64.tar.bz2")
    endif()
endif()

# The CDN path requires '+' to be percent-encoded as %2B.
string(REPLACE "+" "%2B" cef_prebuilt_url_name "${cef_prebuilt_version}")
set(cef_prebuilt_path "${CEF_CDN}/${cef_prebuilt_url_name}")
get_filename_component(cef_local_archive
    "${CMAKE_CURRENT_LIST_DIR}/../${cef_prebuilt_version}" ABSOLUTE)


function(extract_file filename extract_dir)
    message(WARNING "${filename} will extract to ${extract_dir} ...")

    set(temp_dir "${CMAKE_BINARY_DIR}/tmp_for_extract.dir")
    if(EXISTS "${temp_dir}")
        file(REMOVE_RECURSE "${temp_dir}")
    endif()
    file(MAKE_DIRECTORY "${temp_dir}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar -xf "${filename}"
            WORKING_DIRECTORY "${temp_dir}"
            RESULT_VARIABLE extract_result
            ERROR_VARIABLE extract_error)
    if(NOT extract_result EQUAL 0)
        message(FATAL_ERROR "Failed to extract ${filename}: ${extract_error}")
    endif()

    file(GLOB contents "${temp_dir}/*")
    list(LENGTH contents n)
    if(NOT n EQUAL 1 OR NOT IS_DIRECTORY "${contents}")
        set(contents "${temp_dir}")
    endif()

    get_filename_component(contents "${contents}" ABSOLUTE)

    file(INSTALL "${contents}/" DESTINATION ${extract_dir})

    file(REMOVE_RECURSE "${temp_dir}")
endfunction()

function(download_file url filename)
    message(WARNING "Downloading ${filename} from ${url}")
    file(DOWNLOAD "${url}" "${filename}" STATUS download_status SHOW_PROGRESS)
    list(GET download_status 0 download_result)
    if(NOT download_result EQUAL 0)
        list(GET download_status 1 download_error)
        message(FATAL_ERROR "Failed to download ${url}: ${download_error}")
    endif()
endfunction(download_file)

function(prepare_prebuilt_files filepath)
    set(need_download FALSE)

    if(NOT EXISTS ${filepath})
        message(WARNING "No ${filepath} found")
        set(need_download TRUE)
    else()
        if(NOT EXISTS ${filepath}/version.txt)
            message(WARNING "No ${filepath}/version.txt found")
            set(need_download TRUE)
        else()
            file(READ ${filepath}/version.txt local_version)
            if(local_version STREQUAL cef_prebuilt_version)
                message(WARNING "No need to update ${filepath}")
            else()
                set(need_download TRUE)
            endif()
            file(REMOVE_RECURSE ${filepath}/new_version.txt)
        endif()
    endif()

    if(need_download)
        message(WARNING "Need to update ${filepath}")
        file(REMOVE "${filepath}/version.txt")
        file(REMOVE_RECURSE "${filepath}/cmake" "${filepath}/Debug" "${filepath}/Release" "${filepath}/Resources" "${filepath}/libcef_dll" "${filepath}/libcef_dll_wrapper" "${filepath}/include")
        # Also remove the legacy lower-case layout from the old custom Windows package.
        file(REMOVE_RECURSE "${filepath}/debug" "${filepath}/release" "${filepath}/resources")
        file(MAKE_DIRECTORY "${filepath}")
        if(EXISTS "${cef_local_archive}")
            message(STATUS "Using local CEF archive: ${cef_local_archive}")
            extract_file("${cef_local_archive}" "${filepath}")
        else()
            set(download_archive "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt.zip")
            download_file("${cef_prebuilt_path}" "${download_archive}")
            extract_file("${download_archive}" "${filepath}")
            file(REMOVE "${download_archive}")
        endif()

        set(required_files
            include/cef_version.h cmake/FindCEF.cmake libcef_dll/CMakeLists.txt)
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            list(APPEND required_files
                Release/chrome-sandbox Release/libcef.so Release/libEGL.so
                Release/libGLESv2.so Release/libvk_swiftshader.so Release/libvulkan.so.1
                Release/v8_context_snapshot.bin Release/vk_swiftshader_icd.json
                Resources/chrome_100_percent.pak Resources/chrome_200_percent.pak
                Resources/resources.pak Resources/icudtl.dat Resources/locales/en-US.pak)
        endif()
        foreach(required_file ${required_files})
            if(NOT EXISTS "${filepath}/${required_file}")
                message(FATAL_ERROR "Incomplete CEF distribution: missing ${filepath}/${required_file}")
            endif()
        endforeach()
        file(STRINGS "${filepath}/include/cef_version.h" version_definition
            REGEX "^#define CEF_VERSION ")
        if(NOT version_definition STREQUAL "#define CEF_VERSION \"${CEF_VERSION}\"")
            message(FATAL_ERROR "CEF version mismatch in ${filepath}/include/cef_version.h")
        endif()

        ## Needed for making it run on arm64 Linux (makes it check for arm64 or aarch64 instead of just arm64)
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            execute_process(
                COMMAND sed -i "s/\"\\\${CMAKE_HOST_SYSTEM_PROCESSOR}\" STREQUAL \"arm64\"/(\"\\\${CMAKE_HOST_SYSTEM_PROCESSOR}\" STREQUAL \"arm64\" OR \"\\\${CMAKE_HOST_SYSTEM_PROCESSOR}\" STREQUAL \"aarch64\")/" "${filepath}/cmake/cef_variables.cmake"
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
                RESULT_VARIABLE patch_result
                ERROR_VARIABLE patch_error
            )
            if(NOT patch_result EQUAL 0)
                message(FATAL_ERROR "Failed to prepare CEF architecture detection: ${patch_error}")
            endif()
        endif()

        file(WRITE "${filepath}/version.txt" "${cef_prebuilt_version}")
    endif()
endfunction(prepare_prebuilt_files)
