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

.EXAMPLE
    .\build_windows.ps1
    .\build_windows.ps1 -LiteRtLmDir "C:\Projects\LiteRT-LM"
#>

param(
    [string]$LiteRtLmDir = ""
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
$BuildBackup = "$BuildFile.litert_lm_ffi_backup"

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

# Stub source (Bazel cc_binary requires at least one)
@"
// LiteRT-LM C API shared library entry point.
// All C API symbols are exported from engine.cc via __declspec(dllexport).
// This stub exists only because Bazel cc_binary requires at least one source.

#ifdef _WIN32
#include <windows.h>
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    (void)hModule; (void)reason; (void)lpReserved;
    return TRUE;
}
#endif
"@ | Set-Content -Path $StubFile -Encoding UTF8

# Append shared library target
@"

# ======================================================================
# LiteRT-LM-FFI: Shared library target
# (auto-generated by build_windows.ps1 - DO NOT COMMIT to LiteRT-LM)
# ======================================================================
cc_binary(
    name = "litert_lm_capi",
    srcs = ["capi_dll_entry.cc"],
    linkshared = True,
    deps = [":engine"],
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
