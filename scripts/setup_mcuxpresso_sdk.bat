@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
for %%I in ("%SCRIPT_DIR%..") do set REPO_DIR=%%~fI

set DEFAULT_MCUX_WORKSPACE=C:\Users\Qingyu.song\source\nxp\mcuxpresso_sdk\mcuxsdk
set MCUX_INPUT=%~1

if "%MCUX_INPUT%"=="" (
    if defined MCUXSDK_DIR (
        set MCUX_INPUT=%MCUXSDK_DIR%
    ) else (
        set MCUX_INPUT=%DEFAULT_MCUX_WORKSPACE%
    )
)

echo Setting up GenAVB/TSN inside an existing MCUXpresso SDK workspace...
echo GenAVB app repo: %REPO_DIR%
echo MCUX input path: %MCUX_INPUT%
echo.

call :ResolveSdkDir "%MCUX_INPUT%"
if errorlevel 1 exit /b 1

call :DetectMcuxpressoTools

call :CheckAdmin
if errorlevel 1 exit /b 1

call :CheckCompatibleSdk
if errorlevel 1 exit /b 1

call :EnsureRepo "%SDK_DIR%\middleware\gen_avb" "https://github.com/NXP/GenAVB_TSN.git" "1ecbf6e920011bbbd12567d8ac0de09434d79859"
if errorlevel 1 exit /b 1

call :EnsureRepo "%SDK_DIR%\components\rtos-abstraction-layer" "https://github.com/NXP/rtos-abstraction-layer.git" "bede9f04902953adab96c9a7d5121eca3e5dbcc8"
if errorlevel 1 exit /b 1

call :EnsureRepo "%SDK_DIR%\components\rtos-apps" "https://github.com/NXP/rtos-apps.git" "a10b6515aea3610ac8d22b4414235b560d884b3e"
if errorlevel 1 exit /b 1

call :EnsureRepo "%SDK_DIR%\middleware\heterogeneous-multicore" "https://github.com/nxp-real-time-edge-sw/heterogeneous-multicore.git" "20fff5054c15be15a6f7e4053312e483f27223bf"
if errorlevel 1 exit /b 1

call :ApplyPatch "%SDK_DIR%" "netc: Optimize endpoint transmit path" "%REPO_DIR%\patches\0001-netc-Optimize-endpoint-transmit-path.patch"
if errorlevel 1 exit /b 1

call :ApplyPatch "%SDK_DIR%\components" "Runtime debug console output control" "%REPO_DIR%\patches\0001-Runtime-debug-console-output-control.patch"
if errorlevel 1 exit /b 1

call :ApplyPatch "%SDK_DIR%\components" "Use Insert key to enable shell and remove exit" "%REPO_DIR%\patches\0002-Use-Insert-key-to-enable-shell-and-remov.patch"
if errorlevel 1 exit /b 1

call :ApplyPatch "%SDK_DIR%\rtos\freertos\freertos-kernel" "FreeRTOS: Dynamic heap size" "%REPO_DIR%\patches\0001-FreeRTOS-Dynamic-heap-size.patch"
if errorlevel 1 exit /b 1

call :CreateLinks
if errorlevel 1 exit /b 1

echo.
echo ========================================
echo GenAVB/TSN MCUXpresso SDK setup complete
echo ========================================
echo MCUX west workspace: %WEST_ROOT%
echo MCUX SDK root:       %SDK_DIR%
if defined MCUXPRESSO_VENV echo MCUXpresso venv:    %MCUXPRESSO_VENV%
if defined MCUXPRESSO_ARMGCC echo MCUXpresso Arm GCC: %MCUXPRESSO_ARMGCC%
echo.
echo Build from the SDK root, for example:
echo   cd /d "%SDK_DIR%"
echo   west build -p always examples/demo_apps/avb_tsn/tsn_app --toolchain armgcc --config hyperram_release -b evkmimxrt1180 -Dcore_id=cm33
echo.
exit /b 0

:ResolveSdkDir
set INPUT_PATH=%~f1

if exist "%INPUT_PATH%\MCUX_VERSION" (
    set SDK_DIR=%INPUT_PATH%
    for %%I in ("%INPUT_PATH%\..") do set WEST_ROOT=%%~fI
) else if exist "%INPUT_PATH%\mcuxsdk\MCUX_VERSION" (
    set WEST_ROOT=%INPUT_PATH%
    set SDK_DIR=%INPUT_PATH%\mcuxsdk
) else (
    echo Error: Could not find MCUX_VERSION under:
    echo   %INPUT_PATH%
    echo or:
    echo   %INPUT_PATH%\mcuxsdk
    exit /b 1
)

echo MCUX west workspace: %WEST_ROOT%
echo MCUX SDK root:       %SDK_DIR%
echo.
exit /b 0

:DetectMcuxpressoTools
set MCUXPRESSO_TOOLS=%USERPROFILE%\.mcuxpressotools
set MCUXPRESSO_VENV=
set MCUXPRESSO_ARMGCC=

if exist "%MCUXPRESSO_TOOLS%\.mcux-venv-3.12\Scripts\activate.bat" (
    set MCUXPRESSO_VENV=%MCUXPRESSO_TOOLS%\.mcux-venv-3.12
)

if defined ARMGCC_DIR (
    set MCUXPRESSO_ARMGCC=%ARMGCC_DIR%
) else if exist "%MCUXPRESSO_TOOLS%\arm-gnu-toolchain-14.2.rel1-mingw-w64-x86_64-arm-none-eabi\bin\arm-none-eabi-gcc.exe" (
    set MCUXPRESSO_ARMGCC=%MCUXPRESSO_TOOLS%\arm-gnu-toolchain-14.2.rel1-mingw-w64-x86_64-arm-none-eabi
)

if defined MCUXPRESSO_VENV echo Detected MCUXpresso venv:    %MCUXPRESSO_VENV%
if defined MCUXPRESSO_ARMGCC echo Detected MCUXpresso Arm GCC: %MCUXPRESSO_ARMGCC%
echo.
exit /b 0

:CheckAdmin
net session >nul 2>&1
if errorlevel 1 (
    echo Error: This script creates directory symbolic links with mklink.
    echo Please run it from an Administrator Command Prompt.
    exit /b 1
)
exit /b 0

:CheckCompatibleSdk
findstr /C:"VERSION_MAJOR = 12" "%SDK_DIR%\MCUX_VERSION" >nul
if errorlevel 1 (
    echo Error: MCUX SDK major version is not 12. Expected SDK 25.12.00.
    exit /b 1
)

findstr /C:"VERSION_MINOR = 00" "%SDK_DIR%\MCUX_VERSION" >nul
if errorlevel 1 (
    echo Error: MCUX SDK minor version is not 00. Expected SDK 25.12.00.
    exit /b 1
)

for /f %%H in ('git -C "%SDK_DIR%" rev-parse HEAD') do set SDK_HEAD=%%H
if /I not "%SDK_HEAD%"=="4e24c99227fc2b6995ada9ea2ebcbfd4857b9f6c" (
    git -C "%SDK_DIR%" merge-base --is-ancestor 4e24c99227fc2b6995ada9ea2ebcbfd4857b9f6c HEAD >nul 2>&1
    if errorlevel 1 (
        echo Error: mcuxsdk core revision is not the expected 25.12.00 GenAVB base.
        echo Current:  %SDK_HEAD%
        echo Expected: 4e24c99227fc2b6995ada9ea2ebcbfd4857b9f6c
        exit /b 1
    )
)

if exist "%SDK_DIR%\components\.git" (
    for /f %%H in ('git -C "%SDK_DIR%\components" rev-parse HEAD') do set COMPONENTS_HEAD=%%H
    if /I not "!COMPONENTS_HEAD!"=="32db83a295aeed927c0914575d99f64dced771cc" (
        git -C "%SDK_DIR%\components" merge-base --is-ancestor 32db83a295aeed927c0914575d99f64dced771cc HEAD >nul 2>&1
        if errorlevel 1 (
            echo Error: mcuxsdk/components revision is not the expected 25.12.00 GenAVB base.
            echo Current:  !COMPONENTS_HEAD!
            echo Expected: 32db83a295aeed927c0914575d99f64dced771cc
            exit /b 1
        )
    )
) else (
    echo Error: Missing repository: %SDK_DIR%\components
    exit /b 1
)

if exist "%SDK_DIR%\rtos\freertos\freertos-kernel\.git" (
    for /f %%H in ('git -C "%SDK_DIR%\rtos\freertos\freertos-kernel" rev-parse HEAD') do set FREERTOS_HEAD=%%H
    if /I not "!FREERTOS_HEAD!"=="f4ca512430e6d7cd6c530e18ec566c1229f64b22" (
        git -C "%SDK_DIR%\rtos\freertos\freertos-kernel" merge-base --is-ancestor f4ca512430e6d7cd6c530e18ec566c1229f64b22 HEAD >nul 2>&1
        if errorlevel 1 (
            echo Error: FreeRTOS kernel revision is not the expected 25.12.00 GenAVB base.
            echo Current:  !FREERTOS_HEAD!
            echo Expected: f4ca512430e6d7cd6c530e18ec566c1229f64b22
            exit /b 1
        )
    )
) else (
    echo Error: Missing repository: %SDK_DIR%\rtos\freertos\freertos-kernel
    exit /b 1
)

echo SDK compatibility check passed.
echo.
exit /b 0

:EnsureRepo
set TARGET_DIR=%~1
set REPO_URL=%~2
set REPO_REV=%~3

if exist "%TARGET_DIR%\.git" (
    echo Updating existing repository: %TARGET_DIR%
    call :RequireCleanGit "%TARGET_DIR%"
    if errorlevel 1 exit /b 1
    git -C "%TARGET_DIR%" fetch --all --tags
    if errorlevel 1 exit /b 1
    git -C "%TARGET_DIR%" fetch origin "%REPO_REV%"
    if errorlevel 1 exit /b 1
    git -C "%TARGET_DIR%" checkout "%REPO_REV%"
    if errorlevel 1 exit /b 1
) else (
    echo Cloning repository: %TARGET_DIR%
    for %%I in ("%TARGET_DIR%\..") do if not exist "%%~fI" mkdir "%%~fI"
    git clone "%REPO_URL%" "%TARGET_DIR%"
    if errorlevel 1 exit /b 1
    git -C "%TARGET_DIR%" fetch origin "%REPO_REV%"
    if errorlevel 1 exit /b 1
    git -C "%TARGET_DIR%" checkout "%REPO_REV%"
    if errorlevel 1 exit /b 1
)

exit /b 0

:RequireCleanGit
set CHECK_DIR=%~1
for /f "delims=" %%S in ('git -C "%CHECK_DIR%" status --porcelain --untracked-files=no') do (
    echo Error: Repository has local changes:
    echo   %CHECK_DIR%
    echo Commit, stash, or remove those changes before continuing.
    exit /b 1
)
exit /b 0

:ApplyPatch
set PATCH_REPO=%~1
set PATCH_SUBJECT=%~2
set PATCH_FILE=%~3
set FOUND_PATCH=

if not exist "%PATCH_REPO%\.git" (
    echo Error: Patch target is not a git repository:
    echo   %PATCH_REPO%
    exit /b 1
)

git -C "%PATCH_REPO%" log --grep="%PATCH_SUBJECT%" -1 --format=%%H >nul 2>&1
if not errorlevel 1 (
    for /f %%A in ('git -C "%PATCH_REPO%" log --grep^="%PATCH_SUBJECT%" -1 --format^=%%H') do set FOUND_PATCH=%%A
    if defined FOUND_PATCH (
        echo Patch already applied: %PATCH_SUBJECT%
        set FOUND_PATCH=
        exit /b 0
    )
)

call :RequireCleanGit "%PATCH_REPO%"
if errorlevel 1 exit /b 1

echo Applying patch: %PATCH_SUBJECT%
git -C "%PATCH_REPO%" am --3way "%PATCH_FILE%"
if errorlevel 1 (
    echo Error: Failed to apply patch:
    echo   %PATCH_FILE%
    echo Run "git -C "%PATCH_REPO%" am --abort" before trying again.
    exit /b 1
)
exit /b 0

:CreateLinks
echo Creating IDE-visible example mirrors...

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\sync_mcuxpresso_sdk_examples.ps1" -SdkDir "%SDK_DIR%" -RepoDir "%REPO_DIR%"
if errorlevel 1 exit /b 1

echo Creating symbolic links...
if not exist "%SDK_DIR%\devices\RT\RT1180" mkdir "%SDK_DIR%\devices\RT\RT1180"
call :ReplaceLink "%SDK_DIR%\devices\RT\RT1180\MIMXRT118x" "%REPO_DIR%\devices\MIMXRT118x"
if errorlevel 1 exit /b 1

exit /b 0

:ReplaceLink
set LINK_PATH=%~1
set TARGET_PATH=%~2

if not exist "%TARGET_PATH%" (
    echo Error: Link target does not exist:
    echo   %TARGET_PATH%
    exit /b 1
)

if exist "%LINK_PATH%" (
    rmdir "%LINK_PATH%" >nul 2>&1
    if errorlevel 1 (
        echo Error: Existing path is not a removable directory link:
        echo   %LINK_PATH%
        exit /b 1
    )
)

mklink /D "%LINK_PATH%" "%TARGET_PATH%"
if errorlevel 1 exit /b 1
exit /b 0
