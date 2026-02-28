import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/rag_result.dart';
import '../services/speech_service.dart';
import '../services/websocket_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Services
  late final WebSocketService _wsService;
  late final SpeechService _speechService;

  // State
  bool _isListening = false;
  bool _isProcessing = false;
  MicInitResult? _micState;   // null = init not yet attempted
  String _liveTranscript = '';
  String _statusMessage = '';
  RagResult? _lastResult;
  String? _error;

  // Mic pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Stream subscriptions
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();

    // Pulse animation for the mic button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.stop();

    _wsService = WebSocketService();
    _speechService = SpeechService(
      onPartialResult: (text) {
        if (mounted) setState(() => _liveTranscript = text);
      },
      onError: (err) {
        if (mounted) setState(() => _error = err);
      },
    );

    _initServices();
  }

  Future<void> _initServices() async {
    final result = await _speechService.initialize();
    await _wsService.connect();

    // Subscribe to WebSocket streams
    _subs.add(_wsService.statusStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _isProcessing = s == WsStatus.processing;
        if (s == WsStatus.connected) _statusMessage = '';
      });
    }));

    _subs.add(_wsService.statusMessageStream.listen((msg) {
      if (mounted) setState(() => _statusMessage = msg);
    }));

    _subs.add(_wsService.resultStream.listen((result) {
      if (mounted) {
        setState(() {
          _lastResult = result;
          _liveTranscript = result.transcript;
          _isProcessing = false;
          _error = null;
        });
      }
    }));

    _subs.add(_wsService.errorStream.listen((err) {
      if (mounted) setState(() => _error = err);
    }));

    if (mounted) setState(() => _micState = result);
  }

  /// Re-attempt microphone initialisation.
  /// Called when the user taps the mic button while mic is not ready,
  /// covering the case where they granted permission after app launch.
  Future<void> _tryInit() async {
    final result = await _speechService.initialize();
    if (mounted) setState(() => _micState = result);
  }

  Future<void> _startListening() async {
    if (_isListening || _isProcessing) return;

    // If mic is not ready, re-attempt init (handles permission granted later).
    if (_micState != MicInitResult.ready) {
      await _tryInit();
      if (_micState != MicInitResult.ready) return; // still not ready
    }

    setState(() {
      _isListening = true;
      _liveTranscript = '';
      _lastResult = null;
      _error = null;
    });
    _pulseController.repeat(reverse: true);
    await _speechService.startListening();
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;
    setState(() => _isListening = false);
    _pulseController.stop();
    _pulseController.reset();

    // Stop the recorder (we still stop it to release the mic)
    await _speechService.stopListening();

    // Use the on-device STT transcript directly — no need for Whisper
    final transcript = _liveTranscript.trim();
    if (transcript.isEmpty) {
      setState(() => _error = 'کوئی آواز نہیں ملی۔ دوبارہ کوشش کریں۔');
      return;
    }

    setState(() => _isProcessing = true);
    await _wsService.sendTextQuery(transcript);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _wsService.dispose();
    _speechService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────
  //  Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0E1A), Color(0xFF1A1535), Color(0xFF0F0E1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildScrollContent()),
              _buildMicSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.record_voice_over, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'World Bank',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'اردو سوال و جواب — AI',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.notoNastaliqUrdu(
                    fontSize: 13,
                    color: const Color(0xFFA29BFE),
                  ),
                ),
              ],
            ),
          ),
          // Connection indicator
          _ConnectionDot(connected: _wsService.status == WsStatus.connected),
        ],
      ),
    );
  }

  Widget _buildScrollContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _buildErrorCard(),
          if (_isProcessing || _statusMessage.isNotEmpty) _buildStatusCard(),
          if (_liveTranscript.isNotEmpty) _buildTranscriptCard(),
          if (_lastResult != null) _buildAnswerCard(_lastResult!),
          if (_micState == MicInitResult.permissionDenied)
            _buildInactiveCard('مائیکروفون کی اجازت نہیں ملی۔ دوبارہ کوشش کریں۔'),
          if (_micState == MicInitResult.permissionPermanentlyDenied)
            _buildInactiveCard(
              'مائیکروفون مستقل بند ہے۔ ترتیبات میں اجازت دیں۔',
              actionLabel: 'ترتیبات کھولیں',
              onAction: () => openAppSettings(),
            ),
          if (_micState == MicInitResult.sttUnavailable)
            _buildInactiveCard('آواز پہچان دستیاب نہیں۔'),
          if ((_micState == null || _micState == MicInitResult.ready) &&
              _lastResult == null &&
              !_isListening &&
              !_isProcessing &&
              _liveTranscript.isEmpty)
            _buildHintCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHintCard() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.mic_none,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'مائیکروفون بٹن دبائیں اور اردو میں سوال پوچھیں',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.notoNastaliqUrdu(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.4),
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isListening
                      ? const Color(0xFFFF6B6B).withValues(alpha: 0.2)
                      : const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isListening ? '🎙 سن رہا ہے...' : '📝 ٹرانسکرپٹ',
                  style: GoogleFonts.notoNastaliqUrdu(
                    fontSize: 12,
                    color: _isListening
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFFA29BFE),
                  ),
                ),
              ),
              Icon(Icons.record_voice_over,
                  color: const Color(0xFFA29BFE).withValues(alpha: 0.7), size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _liveTranscript,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.notoNastaliqUrdu(
              fontSize: 18,
              color: Colors.white,
              height: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(RagResult result) {
    return _GlassCard(
      accentColor: const Color(0xFF00B894),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '${result.chunksFound} اقتباسات',
                    style: GoogleFonts.notoNastaliqUrdu(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B894).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '🤖 AI جواب',
                  style: GoogleFonts.notoNastaliqUrdu(
                    fontSize: 12,
                    color: const Color(0xFF00B894),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.answer,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.notoNastaliqUrdu(
              fontSize: 18,
              color: Colors.white,
              height: 2.0,
            ),
          ),
          if (result.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: result.sources
                  .map((s) => _SourceChip(label: s))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return _GlassCard(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFA29BFE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMessage.isNotEmpty
                  ? _statusMessage
                  : 'آپ کا سوال پروسیس ہو رہا ہے...',
              textDirection: TextDirection.rtl,
              style: GoogleFonts.notoNastaliqUrdu(
                  fontSize: 14, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return _GlassCard(
      accentColor: const Color(0xFFFF6B6B),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.notoNastaliqUrdu(
                  fontSize: 13, color: const Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInactiveCard(
    String msg, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return _GlassCard(
      accentColor: Colors.orange,
      child: Row(
        children: [
          Expanded(
            child: Text(
              msg,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.notoNastaliqUrdu(
                  fontSize: 14, color: Colors.orange),
            ),
          ),
          if (actionLabel != null && onAction != null) ...
            [
              const SizedBox(width: 10),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel,
                  style: GoogleFonts.notoNastaliqUrdu(
                      fontSize: 13, color: Colors.orangeAccent),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildMicSection() {
    // Mic is always pressable as long as we're not mid-processing.
    // Recording works offline; the audio is sent once WebSocket connects.
    final bool canPress = !_isProcessing;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0F0E1A).withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTapDown: canPress ? (_) => _startListening() : null,
            onTapUp: canPress ? (_) => _stopListening() : null,
            onTapCancel: canPress ? () => _stopListening() : null,
            child: ScaleTransition(
              scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isListening
                        ? [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)]
                        : canPress
                            ? [const Color(0xFF6C5CE7), const Color(0xFFA29BFE)]
                            : [Colors.grey.shade800, Colors.grey.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF6C5CE7))
                          .withValues(alpha: 0.4),
                      blurRadius: _isListening ? 30 : 20,
                      spreadRadius: _isListening ? 6 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  size: 38,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isListening
                ? 'رکنے کے لیے چھوڑیں'
                : _isProcessing
                    ? 'انتظار کریں...'
                    : 'بولنے کے لیے دبائیں',
            style: GoogleFonts.notoNastaliqUrdu(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Reusable Widgets
// ──────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;

  const _GlassCard({
    required this.child,
    this.accentColor = const Color(0xFF6C5CE7),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final bool connected;
  const _ConnectionDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? const Color(0xFF00B894) : const Color(0xFFFF6B6B),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'متصل' : 'منقطع',
          style: GoogleFonts.notoNastaliqUrdu(
            fontSize: 11,
            color: connected ? const Color(0xFF00B894) : const Color(0xFFFF6B6B),
          ),
        ),
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  const _SourceChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}
