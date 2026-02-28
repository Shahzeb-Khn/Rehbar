import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Describes the result of attempting to initialise the microphone.
enum MicInitResult {
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  sttUnavailable,
}

class SpeechService {
  SpeechToText _stt = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();

  bool _sttInitialized = false;
  String _liveTranscript = '';

  // Stream for raw audio bytes (works on Web + Mobile)
  StreamSubscription<Uint8List>? _recordSub;
  final List<int> _audioBuffer = [];

  /// Fired as the user speaks (live partial Urdu text).
  final void Function(String text) onPartialResult;

  /// Fired when an STT error occurs during listening.
  final void Function(String error)? onError;

  SpeechService({required this.onPartialResult, this.onError});

  bool get isReady => _sttInitialized;

  /// Initialise microphone + STT engine.
  Future<MicInitResult> initialize() async {
    _sttInitialized = false;
    _stt = SpeechToText();

    // Permissions on Web don't map perfectly to permission_handler,
    // but the record & speech_to_text plugins handle generic browser prompts.
    if (!kIsWeb) {
      var status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return MicInitResult.permissionPermanentlyDenied;
      }
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return MicInitResult.permissionPermanentlyDenied;
      }
      if (!status.isGranted) {
        return MicInitResult.permissionDenied;
      }
    }

    String? sttError;
    _sttInitialized = await _stt.initialize(
      onStatus: (_) {},
      onError: (SpeechRecognitionError e) {
        sttError = e.errorMsg;
        onError?.call(e.errorMsg);
      },
    );

    if (!_sttInitialized) {
      onError?.call(sttError ?? 'Speech recognition engine unavailable.');
      return MicInitResult.sttUnavailable;
    }

    return MicInitResult.ready;
  }

  /// Start listening and streaming bytes into memory (Cross-platform)
  Future<void> startListening() async {
    if (!_sttInitialized) return;
    _liveTranscript = '';
    _audioBuffer.clear();

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        _liveTranscript = result.recognizedWords;
        onPartialResult(_liveTranscript);
      },
      localeId: 'ur_PK',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );

    // Cross-platform: start streaming bytes into a buffer
    // Web browsers generally only support streaming opus or webm, not AAC.
    final recordStream = await _recorder.startStream(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
    );

    _recordSub = recordStream.listen((data) {
      _audioBuffer.addAll(data);
    });
  }

  /// Stop listening and return the recorded chunks
  Future<Uint8List> stopListening() async {
    await _stt.stop();
    await _recorder.stop();
    
    _recordSub?.cancel();
    _recordSub = null;

    final bytes = Uint8List.fromList(_audioBuffer);
    _audioBuffer.clear();
    
    return bytes;
  }

  bool get isListening => _stt.isListening;
  String get liveTranscript => _liveTranscript;

  void dispose() {
    _recordSub?.cancel();
    _recorder.dispose();
    _stt.cancel();
  }
}
