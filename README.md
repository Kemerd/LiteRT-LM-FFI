# LiteRT-LM-FFI

Prebuilt shared libraries + build scripts for the [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) C API, ready for FFI consumption from **any language** (Dart, Python, Rust, Go, C#, etc.).

**This has never been done before.** Google's LiteRT-LM only ships as a C++ library with a Bazel build system. This repo provides:

1. **One-command build scripts** that compile the C API into a proper shared library (.dll / .so / .dylib)
2. **Prebuilt binaries** for Windows x86_64 (more platforms coming)
3. **Example FFI bindings** (Dart included, more welcome via PR)
4. **The C API header** (`include/engine.h`) for reference

## What is LiteRT-LM?

[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) is Google's C++ library for efficiently running Large Language Models on edge devices. It supports:

- **Models**: Gemma 3 1B, Gemma 3n E2B/E4B, Phi-4-mini, Qwen 2.5, and more
- **Platforms**: Windows, Linux, macOS, Android
- **Backends**: CPU, GPU (WebGPU/Metal/OpenCL), NPU
- **Features**: Streaming, multimodal (text/image/audio), function calling, conversation management

## Quick Start

### Option 1: Use Prebuilt Binaries

Grab the DLLs from `prebuilt/` and load them in your app:

```
prebuilt/
  windows_x86_64/
    litert_lm_capi.dll          # Main C API library
    libLiteRt.dll               # LiteRT runtime
    libLiteRtWebGpuAccelerator.dll  # GPU support
    ...
```

### Option 2: Build from Source

```bash
# Clone LiteRT-LM source
git clone https://github.com/google-ai-edge/LiteRT-LM.git

# Windows
.\build\build_windows.ps1

# Linux / macOS
./build/build_unix.sh
```

**Prerequisites**: Bazel (auto-downloads 7.6.1), C++ compiler (MSVC/Clang), Python 3, Git

## C API Reference

See [`include/engine.h`](include/engine.h) for the full API. Key functions:

```c
// Create engine with model
LiteRtLmEngineSettings* litert_lm_engine_settings_create(
    const char* model_path, const char* backend, ...);
LiteRtLmEngine* litert_lm_engine_create(LiteRtLmEngineSettings* settings);

// Create conversation
LiteRtLmConversationConfig* litert_lm_conversation_config_create(
    LiteRtLmEngine* engine, LiteRtLmSessionConfig* config, ...);
LiteRtLmConversation* litert_lm_conversation_create(
    LiteRtLmEngine* engine, LiteRtLmConversationConfig* config);

// Chat (blocking)
LiteRtLmJsonResponse* litert_lm_conversation_send_message(
    LiteRtLmConversation* conversation, const char* message_json);

// Chat (streaming)
int litert_lm_conversation_send_message_stream(
    LiteRtLmConversation* conversation, const char* message_json,
    void (*callback)(void*, const char*, bool, const char*), void* data);
```

## Examples

### Dart (FFI)

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

final lib = DynamicLibrary.open('litert_lm_capi.dll');
final createSettings = lib.lookupFunction<...>('litert_lm_engine_settings_create');
// See example/dart/ for complete working example
```

### Python (ctypes)

```python
import ctypes

lib = ctypes.CDLL('./litert_lm_capi.dll')  # or .so / .dylib
lib.litert_lm_engine_settings_create.restype = ctypes.c_void_p
lib.litert_lm_engine_settings_create.argtypes = [ctypes.c_char_p] * 4

settings = lib.litert_lm_engine_settings_create(
    b"model.litertlm", b"cpu", None, None)
engine = lib.litert_lm_engine_create(settings)
# ...
```

### Rust

```rust
use std::ffi::CString;

#[link(name = "litert_lm_capi")]
extern "C" {
    fn litert_lm_engine_settings_create(
        model: *const i8, backend: *const i8,
        vision: *const i8, audio: *const i8,
    ) -> *mut std::ffi::c_void;
    fn litert_lm_engine_create(settings: *mut std::ffi::c_void) -> *mut std::ffi::c_void;
}
```

### C# (P/Invoke)

```csharp
[DllImport("litert_lm_capi")]
static extern IntPtr litert_lm_engine_settings_create(
    string modelPath, string backend,
    string visionBackend, string audioBackend);

[DllImport("litert_lm_capi")]
static extern IntPtr litert_lm_engine_create(IntPtr settings);
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| Windows  | x86_64      | ✅ Prebuilt included |
| Linux    | x86_64      | 🔨 Build script ready |
| Linux    | arm64       | 🔨 Build script ready |
| macOS    | arm64       | 🔨 Build script ready |

## Build Scripts - What They Do

The build scripts temporarily inject a `cc_binary(linkshared=True)` target into LiteRT-LM's Bazel build, compile it, copy the output, then clean up. Your LiteRT-LM checkout is left untouched.

Key technical details:
- **`alwayslink = True`**: An intermediate `cc_library` wraps the `:engine` dependency with `alwayslink = True`. Without this, the linker (especially MSVC on Windows) garbage-collects `engine.obj` because nothing in `capi_dll_entry.cc` directly references its symbols. The `__declspec(dllexport)` annotations in `engine.cc` only work if the object is actually linked in — `alwayslink` forces inclusion of all objects.
- **`set_dispatch_lib_dir` patch**: The upstream C API is missing a setter for `litert_dispatch_lib_dir`, which tells the LiteRT runtime where to find GPU accelerator shared libraries (e.g. `libLiteRtWebGpuAccelerator.dll/.so`). Without it, GPU/WebGPU initialization crashes because the runtime can't locate its dependencies. The build scripts temporarily patch `engine.h` and `engine.cc` to add `litert_lm_engine_settings_set_dispatch_lib_dir()`, then restore the originals after compilation.
- **`--clean` flag**: Pass `-Clean` (Windows) or `--clean` (Unix) to wipe the Bazel cache with `bazel clean --expunge` before building. Useful when switching branches or after editing the build script itself.
- Sets `BAZEL_SH` to Git Bash (avoids WSL requirement)
- Sets `BAZEL_VC` to auto-detect MSVC (avoids broken auto-detection)
- Uses short `--output_user_root=C:/b` (avoids 260-char path limit from Rust intermediate files)

## Models

Download `.litertlm` models from [HuggingFace](https://huggingface.co/collections/litert-community):
- [Gemma 3 1B](https://huggingface.co/litert-community/gemma-3-1b-it-int4-litert-lm)
- [Gemma 3n E2B](https://huggingface.co/litert-community/gemma-3n-E2B-it-int4-litert-lm)

## Credits

- [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) by Google AI Edge
- [LiteRT](https://github.com/google-ai-edge/LiteRT) by Google AI Edge
- Build scripts and FFI packaging by this project
