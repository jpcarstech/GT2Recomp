cmake_minimum_required(VERSION 3.20)
set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../psxrecomp" CACHE PATH
    "Path to psxrecomp")
if(NOT EXISTS "${PSXRECOMP_ROOT}/runtime/runtime.cmake")
    message(FATAL_ERROR
        "PSXRecomp runtime is missing: ${PSXRECOMP_ROOT}/runtime/runtime.cmake\n"
        "This project expects the psxrecomp framework checkout at ${PSXRECOMP_ROOT}.\n"
        "Run: git submodule update --init --recursive\n"
        "If psxrecomp/ is not a submodule, set -DPSXRECOMP_ROOT=<path-to-psxrecomp>.")
endif()

project(GT2CombinedRecomp LANGUAGES C CXX)

# --- Opt-in product surfaces (OFF by default in the framework) -------------
# Scaffold prompts / flags fill these. Without recomp-ui, PSX_RECOMP_UI is OFF.
# Setup-host CI requires WIZARD_CMAKE_BLOCK / ENABLE_SETUP_WIZARD (FORCE_SETUP_HOST
# alone does not open first-run / Generate & rebuild).



# Mod packages: one shared tree at the repo root serves every disc title —
# the package carries per-disc [[feature.target]] entries, so each disc's
# menu shows exactly the enhancements that are real for it. A title may
# still override with its own mods/ folder.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/mods/packages")
    set(GT2_MODS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mods")
else()
    set(GT2_MODS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../mods")
endif()

include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

psxrecomp_add_game_runtime(psx-runtime



    WINDOW_TITLE "Gran Turismo 2 (Combined) Recompiled"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
    MAX_PLAYERS 2


    GEN_MARKER "generated/SCUS_944.88_dispatch.c"
    GEN_FULL_GLOB "generated/SCUS_944.88_full_*.c"
    CODEGEN_SETUP_SOURCES codegen_setup.c ../../mods_gt2_silent.c ../../mods_gt2_recomp.c ../../gt2_career.c ../../gameshark_vm.c
    CODEGEN_SETUP_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
)

# Stage this game's mod packages and runtime configs next to the exe, for
# EVERY runtime target that exists (framework stages builtin packages itself).
# Attaching only to psx-runtime silently stopped refreshing build/mods once
# installs switched to building just the PGXP variant — the installed
# manifest went stale.
foreach(_PSX_RT psx-runtime psx-runtime-pgxp)
    if(NOT TARGET ${_PSX_RT})
        continue()
    endif()
    add_custom_command(TARGET ${_PSX_RT} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${GT2_MODS_DIR}/packages"
            "$<TARGET_FILE_DIR:${_PSX_RT}>/mods/packages"
        COMMENT "Staging game mod packages (${_PSX_RT})"
        VERBATIM)
    # Only copy configs that exist — never fail POST_BUILD when
    # game_options.toml is absent.
    foreach(_PSX_RUNTIME_CONFIG game.toml game_options.toml)
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_PSX_RUNTIME_CONFIG}")
            add_custom_command(TARGET ${_PSX_RT} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${CMAKE_CURRENT_SOURCE_DIR}/${_PSX_RUNTIME_CONFIG}"
                    "$<TARGET_FILE_DIR:${_PSX_RT}>/${_PSX_RUNTIME_CONFIG}"
                COMMENT "Staging ${_PSX_RUNTIME_CONFIG} (${_PSX_RT})"
                VERBATIM)
        endif()
    endforeach()
endforeach()
