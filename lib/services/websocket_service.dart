import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../models/rag_result.dart';

enum WsStatus { disconnected, connecting, connected, processing }

class WebSocketService {
  WebSocketChannel? _channel;
  WsStatus _status = WsStatus.disconnected;

  final _statusController = StreamController<WsStatus>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  final _resultController = StreamController<RagResult>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<WsStatus> get statusStream => _statusController.stream;
  Stream<String> get statusMessageStream => _statusMessageController.stream;
  Stream<RagResult> get resultStream => _resultController.stream;
  Stream<String> get errorStream => _errorController.stream;

  WsStatus get status => _status;

  Future<void> connect() async {
    if (_status == WsStatus.connected) return;
    _setStatus(WsStatus.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      await _channel!.ready;
      _setStatus(WsStatus.connected);
      _listen();
    } catch (e) {
      _setStatus(WsStatus.disconnected);
      _errorController.add('Connection failed: $e');
    }
  }

  void _listen() {
    _channel?.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;

          switch (type) {
            case 'status':
              _statusMessageController.add(msg['message'] as String? ?? '');
              _setStatus(WsStatus.processing);
              break;
            case 'result':
              _setStatus(WsStatus.connected);
              _resultController.add(RagResult.fromJson(msg));
              break;
            case 'error':
              _setStatus(WsStatus.connected);
              _errorController.add(msg['message'] as String? ?? 'Unknown error');
              break;
            case 'ack':
            case 'pong':
              break; // silent acknowledgements
            default:
              break;
          }
        } catch (e) {
          _errorController.add('Parse error: $e');
        }
      },
      onDone: () {
        _setStatus(WsStatus.disconnected);
      },
      onError: (error) {
        _setStatus(WsStatus.disconnected);
        _errorController.add('WebSocket error: $error');
      },
    );
  }

  /// Send audio bytes in base64-encoded chunks then signal end
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (_status != WsStatus.connected) return;

    // Send audio as base64 in a single chunk (could chunk in batches for large files)
    final encoded = base64Encode(audioBytes);
    _channel!.sink.add(jsonEncode({
      'type': 'audio_chunk',
      'data': encoded,
    }));

    // Signal end of audio
    _channel!.sink.add(jsonEncode({'type': 'end'}));
    _setStatus(WsStatus.processing);
  }

  /// Send a text transcript directly (bypasses Whisper, uses on-device STT)
  Future<void> sendTextQuery(String transcript) async {
    if (_status != WsStatus.connected) return;

    _channel!.sink.add(jsonEncode({
      'type': 'text_query',
      'transcript': transcript,
    }));
    _setStatus(WsStatus.processing);
  }

  void _setStatus(WsStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _setStatus(WsStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _statusMessageController.close();
    _resultController.close();
    _errorController.close();
  }
}
