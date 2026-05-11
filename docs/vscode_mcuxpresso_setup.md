# MCUXpresso VS Code Setup

This note describes the Windows MCUXpresso VS Code workflow for building and
debugging the GenAVB/TSN examples inside an existing MCUXpresso SDK west
workspace.

## Setup Script

Run the setup script from an Administrator Command Prompt:

```cmd
cd <GenAVB_TSN-rtos-apps>\scripts
setup_mcuxpresso_sdk.bat <mcux-workspace-or-mcuxsdk-root>
```

If no path is passed, the script uses `MCUXSDK_DIR` when it is set. Otherwise it
falls back to the default path in the script.

The script:

- resolves the MCUXpresso SDK root and west workspace root;
- checks that the SDK matches the expected 25.12.00 base revisions;
- clones or updates the required middleware/component repositories;
- applies the required SDK, components, and FreeRTOS patches;
- mirrors the GenAVB/TSN example files into `mcuxsdk\examples` with hardlinks;
- creates the RT1180 device directory symlink:
  `mcuxsdk\devices\RT\RT1180\MIMXRT118x`.

The example mirror is intentionally a hardlink mirror rather than a directory
symlink. This makes the files visible to MCUXpresso VS Code project discovery
while keeping the authoritative source in this repository. Re-run the setup
script after adding or removing files under `boards\src\demo_apps\avb_tsn` or
`boards\<board>\demo_apps\avb_tsn`, because new files need new hardlinks.

## Desired Command-Line Build

Build from the MCUXpresso SDK root, not from this repository:

```cmd
cd /d <mcux-workspace>\mcuxsdk
west build -p always examples/demo_apps/avb_tsn/tsn_app --toolchain armgcc --config release_hybrid -b evkmimxrt1180 -Dcore_id=cm33 -DCONF_FILE=examples/_boards/evkmimxrt1180/demo_apps/avb_tsn/tsn_app/cm33/prj_hybrid.conf
```

For the RT1180 CM33 hybrid TSN bridge + endpoint configuration, the important
parts are:

- `--config release_hybrid`: passed by west to CMake as
  `-DCMAKE_BUILD_TYPE=release_hybrid`;
- `-DCONF_FILE=.../cm33/prj_hybrid.conf`: passed to Kconfig and selects
  `CONFIG_MCUX_PRJSEG_config.board.app_bridge_hybrid=y`.

These two knobs are independent. The build type selects target-specific CMake
behavior, such as linker scripts and target-scoped flags. `CONF_FILE` selects
Kconfig symbols and application features.

For normal LinkServer debugging from external flash, use `release_hybrid`. It
selects the FlexSPI NOR linker script through the RT1180 CM33 board
`reconfig.cmake`. Use `ram_release_hybrid` only when intentionally downloading
and running from RAM.

## MCUXpresso VS Code Preset

MCUXpresso VS Code uses `CMakePresets.json` when triggering CMake builds from
the IDE. It does not automatically translate the west command above, so add a
matching configure preset to the generated file:

```text
<mcux-workspace>\mcuxsdk\examples\demo_apps\avb_tsn\tsn_app\CMakePresets.json
```

Add this entry to `configurePresets`:

```json
{
  "name": "release_hybrid",
  "displayName": "release_hybrid",
  "generator": "Ninja",
  "binaryDir": "${fileDir}/${presetName}",
  "toolchainFile": "$env{SdkRootDirPath}/mcuxsdk/cmake/toolchain/armgcc.cmake",
  "inherits": "release-env",
  "cacheVariables": {
    "APP_DIR": {
      "value": "${fileDir}",
      "type": "PATH"
    },
    "CMAKE_BUILD_TYPE": "release_hybrid",
    "SdkRootDirPath": "$env{SdkRootDirPath}/mcuxsdk",
    "CONFIG_TOOLCHAIN": "armgcc",
    "CMAKE_RUNTIME_OUTPUT_DIRECTORY": "$env{binaryDir}",
    "CMAKE_LIBRARY_OUTPUT_DIRECTORY": "$env{binaryDir}",
    "CMAKE_ARCHIVE_OUTPUT_DIRECTORY": "$env{binaryDir}",
    "WEST": "TRUE",
    "board": "evkmimxrt1180",
    "core_id": "cm33",
    "CONF_FILE": "${fileDir}/../../../_boards/evkmimxrt1180/demo_apps/avb_tsn/tsn_app/cm33/prj_hybrid.conf"
  }
}
```

Add this entry to `buildPresets`:

```json
{
  "name": "release_hybrid",
  "displayName": "release_hybrid",
  "configurePreset": "release_hybrid"
}
```

After editing the preset file, select `release_hybrid` in MCUXpresso VS Code and
reconfigure the project. If an old build directory already exists, delete the
`release_hybrid` directory or run a pristine command-line build once.

The generated preset file is local SDK/IDE state. Do not treat it as the source
of truth for the GenAVB/TSN application. The source of truth for the hybrid mode
is `boards\evkmimxrt1180\demo_apps\avb_tsn\tsn_app\cm33\prj_hybrid.conf` in
this repository.

Use the SDK-root-relative `CONF_FILE` path in `west build` commands. Use the
`${fileDir}` form in `CMakePresets.json`, because VS Code configures from the
example directory and CMake also hashes the file path during Kconfig processing.
