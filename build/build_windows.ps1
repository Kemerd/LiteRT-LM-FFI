<#
.SYNOPSIS
    Builds the LiteRT-LM C API as a shared library (DLL) on Windows.

.DESCRIPTION
    Uses Bazel to compile the LiteRT-LM C API from source into a DLL that
    exports all litert_lm_* symbols for FFI consumption from any language
    (Dart, Python, Rust, Go, C#, etc.).

    Run this ONCE. The output DLL goes to prebuilt/windows_x86_64/.

    Prerequisites:
      - Bazel / Bazelisk (7.6.1 will be auto-downloaded)
      - MSVC (Visual Studio Build Tools 2022+)
      - Python 3.x
      - Git (with Git Bash)

.PARAMETER LiteRtLmDir
    Path to a LiteRT-LM source checkout. If not provided, the script
    searches common locations or prompts you to clone.

.PARAMETER Clean
    Wipe the Bazel cache before building (bazel clean --expunge).
    Use this after changing the build script or when Bazel serves stale artifacts.

.EXAMPLE
    .\build_windows.ps1
    .\build_windows.ps1 -Clean
    .\build_windows.ps1 -LiteRtLmDir "C:\Projects\LiteRT-LM" -Clean
#>

param(
    [string]$LiteRtLmDir = "",
    [switch]$Clean
)

# Note: we do NOT use $ErrorActionPreference = "Stop" globally because
# Bazel/bazelisk writes download progress and warnings to stderr, which
# PowerShell would incorrectly treat as terminating errors.

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  LiteRT-LM C API DLL Builder (Windows)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Resolve paths
# ============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Find LiteRT-LM source directory
if ([string]::IsNullOrEmpty($LiteRtLmDir)) {
    $candidates = @(
        "$RepoRoot\..\LiteRT-LM-ref",
        "$RepoRoot\..\LiteRT-LM",
        "$env:USERPROFILE\LiteRT-LM"
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\c\engine.h") {
            $LiteRtLmDir = (Resolve-Path $c).Path
            break
        }
    }
}

if ([string]::IsNullOrEmpty($LiteRtLmDir) -or -not (Test-Path "$LiteRtLmDir\c\engine.h")) {
    Write-Host "ERROR: LiteRT-LM source not found." -ForegroundColor Red
    Write-Host "Pass -LiteRtLmDir or clone next to this repo:" -ForegroundColor Yellow
    Write-Host "  git clone https://github.com/google-ai-edge/LiteRT-LM.git ..\LiteRT-LM" -ForegroundColor Gray
    exit 1
}

# Output directory
$OutputDir = "$RepoRoot\prebuilt\windows_x86_64"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "LiteRT-LM source: $LiteRtLmDir"
Write-Host "Output dir:       $OutputDir"
Write-Host ""

# ============================================================================
# Verify tools
# ============================================================================

Write-Host "Checking build tools..." -ForegroundColor Gray

$bazel = $null
$bazelSearchPaths = @(
    "$env:APPDATA\npm\bazelisk.cmd",
    "$env:APPDATA\npm\bazel.cmd",
    "$env:LOCALAPPDATA\Programs\bazel\bazel.exe",
    "$env:USERPROFILE\bin\bazelisk.exe",
    "$env:USERPROFILE\bin\bazel.exe"
)

foreach ($cmd in @("bazelisk", "bazel")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) { $bazel = $found.Source; break }
}
if (-not $bazel) {
    foreach ($path in $bazelSearchPaths) {
        if (Test-Path $path) { $bazel = $path; break }
    }
}
if (-not $bazel) {
    Write-Host "ERROR: bazelisk or bazel not found" -ForegroundColor Red
    Write-Host "  Install: npm install -g @bazel/bazelisk" -ForegroundColor Gray
    exit 1
}
Write-Host "  Bazel: $bazel" -ForegroundColor Green

# Run -Clean if requested (wipe Bazel cache entirely)
if ($Clean) {
    Write-Host ""
    Write-Host "Running bazel clean --expunge (this wipes the entire cache)..." -ForegroundColor Yellow
    Push-Location $LiteRtLmDir
    & $bazel clean --expunge 2>&1 | ForEach-Object { Write-Host "  $_" }
    Pop-Location
    Write-Host "  Cache purged." -ForegroundColor Green
}

# Check MSVC
$clExe = Get-Command "cl.exe" -ErrorAction SilentlyContinue
if (-not $clExe) {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -property installationPath 2>$null
        if ($vsPath) {
            Write-Host "  MSVC: $vsPath" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  MSVC: $($clExe.Source)" -ForegroundColor Green
}

Write-Host ""

# ============================================================================
# Create temporary shared library target
# ============================================================================

Write-Host "Setting up build target..." -ForegroundColor Gray

$BuildFile = "$LiteRtLmDir\c\BUILD"
$StubFile = "$LiteRtLmDir\c\capi_dll_entry.cc"
$HeaderFile = "$LiteRtLmDir\c\engine.h"
$SourceFile = "$LiteRtLmDir\c\engine.cc"
$BuildBackup = "$BuildFile.litert_lm_ffi_backup"
$HeaderBackup = "$HeaderFile.litert_lm_ffi_backup"
$SourceBackup = "$SourceFile.litert_lm_ffi_backup"

# Strip any leftover targets from previous runs
$buildContent = Get-Content -Path $BuildFile -Raw
$marker = "# LiteRT-LM-FFI: Shared library target"
if ($buildContent -match [regex]::Escape($marker)) {
    Write-Host "  Cleaning leftover targets from c/BUILD..." -ForegroundColor Yellow
    $idx = $buildContent.IndexOf($marker) - 80
    if ($idx -gt 0) {
        $buildContent = $buildContent.Substring(0, $idx).TrimEnd() + "`n"
        Set-Content -Path $BuildFile -Value $buildContent -Encoding UTF8 -NoNewline
    }
}

Copy-Item -Path $BuildFile -Destination $BuildBackup -Force
Copy-Item -Path $HeaderFile -Destination $HeaderBackup -Force
Copy-Item -Path $SourceFile -Destination $SourceBackup -Force

# ============================================================================
# Patch engine.h: add litert_lm_engine_settings_set_dispatch_lib_dir
# ============================================================================
# The upstream C API is missing a setter for the LiteRT dispatch library
# directory. Without it, the GPU/WebGPU accelerator can't find its DLLs
# (libLiteRtWebGpuAccelerator.dll, etc.) and crashes during init.

$headerContent = Get-Content -Path $HeaderFile -Raw
$dispatchDeclMarker = "litert_lm_engine_settings_set_dispatch_lib_dir"
if ($headerContent -notmatch [regex]::Escape($dispatchDeclMarker)) {
    $patchDecl = @"

// Sets the LiteRT dispatch library directory. This tells the runtime where
// to find accelerator DLLs (e.g. libLiteRtWebGpuAccelerator.dll). If not
// set, the runtime searches environment variables / system PATH, which
// may fail for bundled apps.
//
// @param settings The engine settings.
// @param dir The directory containing LiteRT accelerator libraries.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_dispatch_lib_dir(
    LiteRtLmEngineSettings* settings, const char* dir);

"@
    $headerContent = $headerContent -replace '(?m)(#ifdef __cplusplus\r?\n\}  // extern "C")', "$patchDecl`$1"
    Set-Content -Path $HeaderFile -Value $headerContent -Encoding UTF8 -NoNewline
    Write-Host "  Patched engine.h: added set_dispatch_lib_dir declaration" -ForegroundColor Green
}

# ============================================================================
# Patch engine.cc: implement litert_lm_engine_settings_set_dispatch_lib_dir
# ============================================================================

$sourceContent = Get-Content -Path $SourceFile -Raw
if ($sourceContent -notmatch [regex]::Escape($dispatchDeclMarker)) {
    $patchImpl = @"

void litert_lm_engine_settings_set_dispatch_lib_dir(
    LiteRtLmEngineSettings* settings, const char* dir) {
  if (settings && settings->settings && dir) {
    // Set on main executor — this is where the GPU/WebGPU accelerator
    // (libLiteRtWebGpuAccelerator.dll) gets loaded from.
    settings->settings->GetMutableMainExecutorSettings()
        .SetLitertDispatchLibDir(dir);
    // Also set on vision executor if it exists (returns std::optional).
    auto vision = settings->settings->GetMutableVisionExecutorSettings();
    if (vision.has_value()) {
      vision->SetLitertDispatchLibDir(dir);
    }
  }
}

"@
    $sourceContent = $sourceContent -replace '(?m)(^\}  // extern "C")', "$patchImpl`$1"
    Set-Content -Path $SourceFile -Value $sourceContent -Encoding UTF8 -NoNewline
    Write-Host "  Patched engine.cc: added set_dispatch_lib_dir implementation" -ForegroundColor Green
}

# Stub source that explicitly references every C API function.
# This is the nuclear option: even if alwayslink is defeated by Bazel flags
# (--legacy_whole_archive=0, /OPT:REF, etc.), the linker MUST keep these
# symbols because they are directly referenced from this translation unit.
@"
// =======================================================================
// LiteRT-LM C API shared library entry point.
// This stub forces the linker to include every exported C API symbol by
// taking their addresses into a volatile array. Without this, MSVC's
// /OPT:REF + Bazel's --legacy_whole_archive=0 can strip engine.obj
// from the final DLL even with alwayslink = True.
// =======================================================================

#include "engine.h"
#include <stddef.h>

#ifdef _WIN32
#include <windows.h>
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    (void)hModule; (void)reason; (void)lpReserved;
    return TRUE;
}
#endif

// Force the linker to keep every C API symbol by referencing them.
// The volatile qualifier prevents the compiler from optimising this away.
volatile const void* litert_lm_force_exports[] = {
    (const void*)&litert_lm_set_min_log_level,
    (const void*)&litert_lm_engine_settings_create,
    (const void*)&litert_lm_engine_settings_delete,
    (const void*)&litert_lm_engine_settings_set_max_num_tokens,
    (const void*)&litert_lm_engine_settings_set_cache_dir,
    (const void*)&litert_lm_engine_settings_set_dispatch_lib_dir,
    (const void*)&litert_lm_engine_settings_set_activation_data_type,
    (const void*)&litert_lm_engine_settings_enable_benchmark,
    (const void*)&litert_lm_engine_create,
    (const void*)&litert_lm_engine_delete,
    (const void*)&litert_lm_engine_create_session,
    (const void*)&litert_lm_session_delete,
    (const void*)&litert_lm_session_generate_content,
    (const void*)&litert_lm_session_generate_content_stream,
    (const void*)&litert_lm_session_get_benchmark_info,
    (const void*)&litert_lm_session_config_create,
    (const void*)&litert_lm_session_config_set_max_output_tokens,
    (const void*)&litert_lm_session_config_set_sampler_params,
    (const void*)&litert_lm_session_config_delete,
    (const void*)&litert_lm_responses_delete,
    (const void*)&litert_lm_responses_get_num_candidates,
    (const void*)&litert_lm_responses_get_response_text_at,
    (const void*)&litert_lm_conversation_config_create,
    (const void*)&litert_lm_conversation_config_delete,
    (const void*)&litert_lm_conversation_create,
    (const void*)&litert_lm_conversation_delete,
    (const void*)&litert_lm_conversation_send_message,
    (const void*)&litert_lm_conversation_send_message_stream,
    (const void*)&litert_lm_conversation_cancel_process,
    (const void*)&litert_lm_conversation_get_benchmark_info,
    (const void*)&litert_lm_json_response_delete,
    (const void*)&litert_lm_json_response_get_string,
    (const void*)&litert_lm_benchmark_info_delete,
    (const void*)&litert_lm_benchmark_info_get_time_to_first_token,
    (const void*)&litert_lm_benchmark_info_get_num_prefill_turns,
    (const void*)&litert_lm_benchmark_info_get_num_decode_turns,
    (const void*)&litert_lm_benchmark_info_get_prefill_token_count_at,
    (const void*)&litert_lm_benchmark_info_get_decode_token_count_at,
    (const void*)&litert_lm_benchmark_info_get_prefill_tokens_per_sec_at,
    (const void*)&litert_lm_benchmark_info_get_decode_tokens_per_sec_at,
};
"@ | Set-Content -Path $StubFile -Encoding UTF8

# Append shared library target.
# The "engine_alwayslink" wrapper forces the linker to include ALL objects
# from the :engine cc_library. Combined with the explicit references in
# capi_dll_entry.cc above, this guarantees all C API symbols are exported.
@"

# ======================================================================
# LiteRT-LM-FFI: Shared library target
# (auto-generated by build_windows.ps1 - DO NOT COMMIT to LiteRT-LM)
# ======================================================================
cc_library(
    name = "engine_alwayslink",
    deps = [":engine"],
    alwayslink = True,
)

cc_binary(
    name = "litert_lm_capi",
    srcs = ["capi_dll_entry.cc"],
    linkshared = True,
    deps = [":engine_alwayslink"],
    visibility = ["//visibility:public"],
)
"@ | Add-Content -Path $BuildFile -Encoding UTF8

Write-Host "  Created cc_binary(linkshared=True) target: //c:litert_lm_capi" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Build
# ============================================================================

try {
    Write-Host "Building LiteRT-LM C API DLL..." -ForegroundColor Cyan
    Write-Host "  First build downloads deps + compiles everything (~5-15 min)" -ForegroundColor Gray
    Write-Host "  Subsequent builds are near-instant (Bazel caches everything)" -ForegroundColor Gray
    Write-Host ""

    Push-Location $LiteRtLmDir

    # Use Git Bash (not WSL) for Bazel shell commands
    $gitBash = "C:\Program Files\Git\bin\bash.exe"
    if (Test-Path $gitBash) {
        $env:BAZEL_SH = $gitBash
        Write-Host "  BAZEL_SH=$gitBash" -ForegroundColor DarkGray
    }

    # Point Bazel to MSVC
    if (-not $env:BAZEL_VC) {
        $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vsWhere) {
            $vsPath = & $vsWhere -latest -property installationPath 2>$null
            if ($vsPath -and (Test-Path "$vsPath\VC")) {
                $env:BAZEL_VC = "$vsPath\VC"
                Write-Host "  BAZEL_VC=$($env:BAZEL_VC)" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Short output_user_root avoids Windows 260-char path limit
    # (Rust proc-macro intermediate files have extremely long names)
    & $bazel --output_user_root=C:/b build //c:litert_lm_capi --config=windows 2>&1 | ForEach-Object {
        Write-Host "  $_"
    }
    $buildExitCode = $LASTEXITCODE

    $ErrorActionPreference = $prevEAP

    if ($buildExitCode -ne 0) {
        throw "Bazel build failed with exit code $buildExitCode"
    }

    Pop-Location

    Write-Host ""
    Write-Host "Build succeeded!" -ForegroundColor Green

    # ========================================================================
    # Copy output
    # ========================================================================

    Write-Host ""
    Write-Host "Copying build output..." -ForegroundColor Gray

    $dllPath = "$LiteRtLmDir\bazel-bin\c\litert_lm_capi.dll"
    if (-not (Test-Path $dllPath)) {
        foreach ($alt in @("$LiteRtLmDir\bazel-bin\c\litert_lm_capi.dll","$LiteRtLmDir\bazel-bin\c\liblitert_lm_capi.dll")) {
            if (Test-Path $alt) { $dllPath = $alt; break }
        }
    }

    if (Test-Path $dllPath) {
        Copy-Item -Path $dllPath -Destination "$OutputDir\litert_lm_capi.dll" -Force
        $size = [math]::Round((Get-Item $dllPath).Length / 1MB, 1)
        Write-Host "  litert_lm_capi.dll ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: DLL not found at: $dllPath" -ForegroundColor Yellow
    }

    # Copy prebuilt accelerator DLLs
    $prebuiltDir = "$LiteRtLmDir\prebuilt\windows_x86_64"
    if (Test-Path $prebuiltDir) {
        Get-ChildItem -Path $prebuiltDir -Filter "*.dll" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination "$OutputDir\$($_.Name)" -Force
            Write-Host "  $($_.Name) (accelerator)" -ForegroundColor Green
        }
    }

} finally {
    Write-Host ""
    Write-Host "Cleaning up temporary build files..." -ForegroundColor Gray

    if (Test-Path $BuildBackup) {
        Copy-Item -Path $BuildBackup -Destination $BuildFile -Force
        Remove-Item -Path $BuildBackup -Force
        Write-Host "  Restored original c/BUILD" -ForegroundColor Green
    }
    if (Test-Path $HeaderBackup) {
        Copy-Item -Path $HeaderBackup -Destination $HeaderFile -Force
        Remove-Item -Path $HeaderBackup -Force
        Write-Host "  Restored original c/engine.h" -ForegroundColor Green
    }
    if (Test-Path $SourceBackup) {
        Copy-Item -Path $SourceBackup -Destination $SourceFile -Force
        Remove-Item -Path $SourceBackup -Force
        Write-Host "  Restored original c/engine.cc" -ForegroundColor Green
    }
    if (Test-Path $StubFile) {
        Remove-Item -Path $StubFile -Force
        Write-Host "  Removed capi_dll_entry.cc" -ForegroundColor Green
    }
}

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output: $OutputDir" -ForegroundColor White
Get-ChildItem -Path $OutputDir -Filter "*.dll" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 1)
    Write-Host "  $($_.Name) ($size MB)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Load litert_lm_capi.dll from your app via FFI (Dart, Python, Rust, C#, etc.)" -ForegroundColor Cyan
Write-Host "See include/engine.h for the full C API reference." -ForegroundColor Cyan
