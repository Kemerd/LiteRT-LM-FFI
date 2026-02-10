// ============================================================================
// LiteRT-LM FFI Example - Dart
// ============================================================================
//
// Demonstrates loading the LiteRT-LM shared library and running a simple
// chat conversation using the Conversation API via dart:ffi.
//
// Usage:
//   dart run bin/example.dart <path-to-model.litertlm> [path-to-litert_lm_capi.dll]
//
// The second argument is optional - it defaults to looking in ../../prebuilt/.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../lib/litert_lm_bindings.dart';

/// Resolve the shared library path for the current platform.
String resolveLibraryPath(String? explicitPath) {
  if (explicitPath != null && File(explicitPath).existsSync()) {
    return explicitPath;
  }

  // Check prebuilt/ relative to this example
  final scriptDir = File(Platform.script.toFilePath()).parent.parent.parent.parent.path;

  final String libName;
  final String platform;
  if (Platform.isWindows) {
    libName = 'litert_lm_capi.dll';
    platform = 'windows_x86_64';
  } else if (Platform.isMacOS) {
    libName = 'liblitert_lm_capi.dylib';
    platform = 'macos_arm64';
  } else {
    libName = 'liblitert_lm_capi.so';
    platform = 'linux_x86_64';
  }

  final prebuiltPath = '$scriptDir/prebuilt/$platform/$libName';
  if (File(prebuiltPath).existsSync()) return prebuiltPath;

  stderr.writeln('ERROR: Could not find $libName');
  stderr.writeln('Looked in: $prebuiltPath');
  stderr.writeln('Run the build script first or pass the path as second argument.');
  exit(1);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/example.dart <model.litertlm> [library-path]');
    exit(1);
  }

  final modelPath = args[0];
  final libraryPath = resolveLibraryPath(args.length > 1 ? args[1] : null);

  print('Loading library: $libraryPath');
  final bindings = LiteRtLmBindings.open(libraryPath);

  // Suppress verbose logging
  bindings.setMinLogLevel(2); // WARNING level

  // Create engine settings
  print('Creating engine with model: $modelPath');
  final modelPathNative = modelPath.toNativeUtf8();
  final backendNative = 'cpu'.toNativeUtf8();
  final nullPtr = Pointer<Utf8>.fromAddress(0);

  final settings = bindings.engineSettingsCreate(
    modelPathNative,
    backendNative,
    nullPtr, // vision backend
    nullPtr, // audio backend
  );

  if (settings.address == 0) {
    stderr.writeln('ERROR: Failed to create engine settings');
    exit(1);
  }

  // Create engine
  final engine = bindings.engineCreate(settings);
  if (engine.address == 0) {
    stderr.writeln('ERROR: Failed to create engine');
    bindings.engineSettingsDelete(settings);
    exit(1);
  }
  print('Engine created successfully!');

  // Create session config
  final sessionConfig = bindings.sessionConfigCreate();

  // Create conversation config
  final conversationConfig = bindings.conversationConfigCreate(
    engine,
    sessionConfig,
    nullPtr, // system message
    nullPtr, // tools
    nullPtr, // messages
    false,   // constrained decoding
  );

  if (conversationConfig.address == 0) {
    stderr.writeln('ERROR: Failed to create conversation config');
    exit(1);
  }

  // Create conversation
  final conversation = bindings.conversationCreate(engine, conversationConfig);
  if (conversation.address == 0) {
    stderr.writeln('ERROR: Failed to create conversation');
    exit(1);
  }

  print('Conversation ready! Type your message (or "quit" to exit):\n');

  // Chat loop
  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();
    if (input == null || input.toLowerCase() == 'quit') break;

    // Build JSON message
    final message = jsonEncode({
      'role': 'user',
      'content': input,
    });
    final messageNative = message.toNativeUtf8();

    // Send message (blocking)
    final response = bindings.conversationSendMessage(conversation, messageNative);
    malloc.free(messageNative);

    if (response.address == 0) {
      print('Model: [error - null response]');
      continue;
    }

    // Get response text
    final responseStr = bindings.jsonResponseGetString(response);
    if (responseStr.address != 0) {
      print('Model: ${responseStr.toDartString()}');
    } else {
      print('Model: [empty response]');
    }
    bindings.jsonResponseDelete(response);
    print('');
  }

  // Cleanup
  print('\nCleaning up...');
  bindings.conversationDelete(conversation);
  bindings.conversationConfigDelete(conversationConfig);
  bindings.sessionConfigDelete(sessionConfig);
  bindings.engineDelete(engine);
  bindings.engineSettingsDelete(settings);
  malloc.free(modelPathNative);
  malloc.free(backendNative);

  print('Done!');
}
