// ============================================================================
// LiteRT-LM FFI Bindings for Dart
// ============================================================================
//
// Hand-written dart:ffi bindings for the LiteRT-LM C API.
// Maps directly to the exported symbols in:
//   - litert_lm_capi.dll       (Windows)
//   - liblitert_lm_capi.so     (Linux)
//   - liblitert_lm_capi.dylib  (macOS)
//
// Reference: include/engine.h
//
// This is a standalone file - copy it into any Dart/Flutter project.
// ============================================================================

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ============================================================================
// Opaque handle typedefs
// ============================================================================

typedef LiteRtLmEngine = Void;
typedef LiteRtLmSession = Void;
typedef LiteRtLmResponses = Void;
typedef LiteRtLmEngineSettings = Void;
typedef LiteRtLmBenchmarkInfo = Void;
typedef LiteRtLmConversation = Void;
typedef LiteRtLmJsonResponse = Void;
typedef LiteRtLmSessionConfig = Void;
typedef LiteRtLmConversationConfig = Void;

// ============================================================================
// Enums
// ============================================================================

abstract class SamplerType {
  static const int unspecified = 0;
  static const int topK = 1;
  static const int topP = 2;
  static const int greedy = 3;
}

abstract class InputDataType {
  static const int text = 0;
  static const int image = 1;
  static const int audio = 2;
  static const int audioEnd = 3;
}

// ============================================================================
// Structs
// ============================================================================

final class LiteRtLmSamplerParams extends Struct {
  @Int32()
  external int type;
  @Int32()
  external int topK;
  @Float()
  external double topP;
  @Float()
  external double temperature;
  @Int32()
  external int seed;
}

final class InputData extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> data;
  @Size()
  external int size;
}

// ============================================================================
// Stream callback
// ============================================================================

typedef LiteRtLmStreamCallbackNative = Void Function(
  Pointer<Void> callbackData,
  Pointer<Utf8> chunk,
  Bool isFinal,
  Pointer<Utf8> errorMsg,
);

typedef LiteRtLmStreamCallbackPtr
    = Pointer<NativeFunction<LiteRtLmStreamCallbackNative>>;

// ============================================================================
// Native function typedefs
// ============================================================================

// Logging
typedef _SetMinLogLevelNative = Void Function(Int32 level);
typedef SetMinLogLevel = void Function(int level);

// Engine Settings
typedef _EngineSettingsCreateNative = Pointer<LiteRtLmEngineSettings> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef EngineSettingsCreate = Pointer<LiteRtLmEngineSettings> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _EngineSettingsDeleteNative = Void Function(Pointer<LiteRtLmEngineSettings>);
typedef EngineSettingsDelete = void Function(Pointer<LiteRtLmEngineSettings>);
typedef _EngineSettingsSetMaxNumTokensNative = Void Function(Pointer<LiteRtLmEngineSettings>, Int32);
typedef EngineSettingsSetMaxNumTokens = void Function(Pointer<LiteRtLmEngineSettings>, int);
typedef _EngineSettingsSetCacheDirNative = Void Function(Pointer<LiteRtLmEngineSettings>, Pointer<Utf8>);
typedef EngineSettingsSetCacheDir = void Function(Pointer<LiteRtLmEngineSettings>, Pointer<Utf8>);

// Engine
typedef _EngineCreateNative = Pointer<LiteRtLmEngine> Function(Pointer<LiteRtLmEngineSettings>);
typedef EngineCreate = Pointer<LiteRtLmEngine> Function(Pointer<LiteRtLmEngineSettings>);
typedef _EngineDeleteNative = Void Function(Pointer<LiteRtLmEngine>);
typedef EngineDelete = void Function(Pointer<LiteRtLmEngine>);

// Session Config
typedef _SessionConfigCreateNative = Pointer<LiteRtLmSessionConfig> Function();
typedef SessionConfigCreate = Pointer<LiteRtLmSessionConfig> Function();
typedef _SessionConfigDeleteNative = Void Function(Pointer<LiteRtLmSessionConfig>);
typedef SessionConfigDelete = void Function(Pointer<LiteRtLmSessionConfig>);

// Session
typedef _EngineCreateSessionNative = Pointer<LiteRtLmSession> Function(Pointer<LiteRtLmEngine>, Pointer<LiteRtLmSessionConfig>);
typedef EngineCreateSession = Pointer<LiteRtLmSession> Function(Pointer<LiteRtLmEngine>, Pointer<LiteRtLmSessionConfig>);
typedef _SessionDeleteNative = Void Function(Pointer<LiteRtLmSession>);
typedef SessionDelete = void Function(Pointer<LiteRtLmSession>);

// Conversation Config
typedef _ConversationConfigCreateNative = Pointer<LiteRtLmConversationConfig> Function(
    Pointer<LiteRtLmEngine>, Pointer<LiteRtLmSessionConfig>,
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef ConversationConfigCreate = Pointer<LiteRtLmConversationConfig> Function(
    Pointer<LiteRtLmEngine>, Pointer<LiteRtLmSessionConfig>,
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, bool);
typedef _ConversationConfigDeleteNative = Void Function(Pointer<LiteRtLmConversationConfig>);
typedef ConversationConfigDelete = void Function(Pointer<LiteRtLmConversationConfig>);

// Conversation
typedef _ConversationCreateNative = Pointer<LiteRtLmConversation> Function(Pointer<LiteRtLmEngine>, Pointer<LiteRtLmConversationConfig>);
typedef ConversationCreate = Pointer<LiteRtLmConversation> Function(Pointer<LiteRtLmEngine>, Pointer<LiteRtLmConversationConfig>);
typedef _ConversationDeleteNative = Void Function(Pointer<LiteRtLmConversation>);
typedef ConversationDelete = void Function(Pointer<LiteRtLmConversation>);
typedef _ConversationSendMessageNative = Pointer<LiteRtLmJsonResponse> Function(Pointer<LiteRtLmConversation>, Pointer<Utf8>);
typedef ConversationSendMessage = Pointer<LiteRtLmJsonResponse> Function(Pointer<LiteRtLmConversation>, Pointer<Utf8>);
typedef _ConversationSendMessageStreamNative = Int32 Function(Pointer<LiteRtLmConversation>, Pointer<Utf8>, LiteRtLmStreamCallbackPtr, Pointer<Void>);
typedef ConversationSendMessageStream = int Function(Pointer<LiteRtLmConversation>, Pointer<Utf8>, LiteRtLmStreamCallbackPtr, Pointer<Void>);

// JSON Response
typedef _JsonResponseDeleteNative = Void Function(Pointer<LiteRtLmJsonResponse>);
typedef JsonResponseDelete = void Function(Pointer<LiteRtLmJsonResponse>);
typedef _JsonResponseGetStringNative = Pointer<Utf8> Function(Pointer<LiteRtLmJsonResponse>);
typedef JsonResponseGetString = Pointer<Utf8> Function(Pointer<LiteRtLmJsonResponse>);

// ============================================================================
// Bindings class - loads library and resolves all symbols
// ============================================================================

class LiteRtLmBindings {
  LiteRtLmBindings._(this._lib);
  final DynamicLibrary _lib;

  factory LiteRtLmBindings.open(String libraryPath) {
    final lib = DynamicLibrary.open(libraryPath);
    return LiteRtLmBindings._(lib).._resolveAll();
  }

  late final SetMinLogLevel setMinLogLevel;
  late final EngineSettingsCreate engineSettingsCreate;
  late final EngineSettingsDelete engineSettingsDelete;
  late final EngineSettingsSetMaxNumTokens engineSettingsSetMaxNumTokens;
  late final EngineSettingsSetCacheDir engineSettingsSetCacheDir;
  late final EngineCreate engineCreate;
  late final EngineDelete engineDelete;
  late final SessionConfigCreate sessionConfigCreate;
  late final SessionConfigDelete sessionConfigDelete;
  late final EngineCreateSession engineCreateSession;
  late final SessionDelete sessionDelete;
  late final ConversationConfigCreate conversationConfigCreate;
  late final ConversationConfigDelete conversationConfigDelete;
  late final ConversationCreate conversationCreate;
  late final ConversationDelete conversationDelete;
  late final ConversationSendMessage conversationSendMessage;
  late final ConversationSendMessageStream conversationSendMessageStream;
  late final JsonResponseDelete jsonResponseDelete;
  late final JsonResponseGetString jsonResponseGetString;

  void _resolveAll() {
    setMinLogLevel = _lib.lookupFunction<_SetMinLogLevelNative, SetMinLogLevel>('litert_lm_set_min_log_level');
    engineSettingsCreate = _lib.lookupFunction<_EngineSettingsCreateNative, EngineSettingsCreate>('litert_lm_engine_settings_create');
    engineSettingsDelete = _lib.lookupFunction<_EngineSettingsDeleteNative, EngineSettingsDelete>('litert_lm_engine_settings_delete');
    engineSettingsSetMaxNumTokens = _lib.lookupFunction<_EngineSettingsSetMaxNumTokensNative, EngineSettingsSetMaxNumTokens>('litert_lm_engine_settings_set_max_num_tokens');
    engineSettingsSetCacheDir = _lib.lookupFunction<_EngineSettingsSetCacheDirNative, EngineSettingsSetCacheDir>('litert_lm_engine_settings_set_cache_dir');
    engineCreate = _lib.lookupFunction<_EngineCreateNative, EngineCreate>('litert_lm_engine_create');
    engineDelete = _lib.lookupFunction<_EngineDeleteNative, EngineDelete>('litert_lm_engine_delete');
    sessionConfigCreate = _lib.lookupFunction<_SessionConfigCreateNative, SessionConfigCreate>('litert_lm_session_config_create');
    sessionConfigDelete = _lib.lookupFunction<_SessionConfigDeleteNative, SessionConfigDelete>('litert_lm_session_config_delete');
    engineCreateSession = _lib.lookupFunction<_EngineCreateSessionNative, EngineCreateSession>('litert_lm_engine_create_session');
    sessionDelete = _lib.lookupFunction<_SessionDeleteNative, SessionDelete>('litert_lm_session_delete');
    conversationConfigCreate = _lib.lookupFunction<_ConversationConfigCreateNative, ConversationConfigCreate>('litert_lm_conversation_config_create');
    conversationConfigDelete = _lib.lookupFunction<_ConversationConfigDeleteNative, ConversationConfigDelete>('litert_lm_conversation_config_delete');
    conversationCreate = _lib.lookupFunction<_ConversationCreateNative, ConversationCreate>('litert_lm_conversation_create');
    conversationDelete = _lib.lookupFunction<_ConversationDeleteNative, ConversationDelete>('litert_lm_conversation_delete');
    conversationSendMessage = _lib.lookupFunction<_ConversationSendMessageNative, ConversationSendMessage>('litert_lm_conversation_send_message');
    conversationSendMessageStream = _lib.lookupFunction<_ConversationSendMessageStreamNative, ConversationSendMessageStream>('litert_lm_conversation_send_message_stream');
    jsonResponseDelete = _lib.lookupFunction<_JsonResponseDeleteNative, JsonResponseDelete>('litert_lm_json_response_delete');
    jsonResponseGetString = _lib.lookupFunction<_JsonResponseGetStringNative, JsonResponseGetString>('litert_lm_json_response_get_string');
  }
}
