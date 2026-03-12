import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class SpeechToTextScreen extends StatefulWidget {
  const SpeechToTextScreen({super.key});

  @override
  State<SpeechToTextScreen> createState() => _SpeechToTextScreenState();
}

class _SpeechToTextScreenState extends State<SpeechToTextScreen>
    with WidgetsBindingObserver {
  // ── Speech recogniser ────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _transcribedText = '';
  double _confidence = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSpeech();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isListening) _speech.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isListening) _stopListening();
    }
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnack('Microphone permission denied. Please enable in Settings.');
      return;
    }
    final available = await _speech.initialize(
      onError: (e) {
        debugPrint('STT error: $e');
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (s) {
        debugPrint('STT status: $s');
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _showSnack('Speech recognition not available on this device.');
      return;
    }
    setState(() {
      _isListening = true;
      _transcribedText = '';
      _confidence = 0;
    });
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _transcribedText = result.recognizedWords;
            _confidence = result.confidence;
          });
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _clearText() => setState(() {
        _transcribedText = '';
        _confidence = 0;
      });

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFF00E5FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech → Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            if (_isListening) await _stopListening();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          if (_transcribedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _clearText,
              tooltip: 'Clear',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 14),

              // ── Transcription display box ──────────────────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isListening
                          ? accent.withOpacity(0.85)
                          : accent.withOpacity(0.18),
                      width: _isListening ? 2.5 : 1.5,
                    ),
                  ),
                  child: _buildTranscriptionView(theme, accent),
                ),
              ),

              const SizedBox(height: 14),

              // ── Confidence bar ─────────────────────────────────────
              if (_confidence > 0 && _transcribedText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(
                        'Confidence: ${(_confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _confidence,
                            backgroundColor: accent.withOpacity(0.12),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(accent),
                            minHeight: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Mic button ─────────────────────────────────────────
              Semantics(
                button: true,
                label: _isListening ? 'Stop listening' : 'Start listening',
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening ? Colors.red.shade700 : accent,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.red : accent)
                              .withOpacity(0.4),
                          blurRadius: _isListening ? 30 : 14,
                          spreadRadius: _isListening ? 6 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                      color: Colors.black,
                      size: 58,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _isListening ? 'Tap to STOP' : 'Tap to SPEAK',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: _isListening ? Colors.red.shade400 : accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptionView(ThemeData theme, Color accent) {
    if (_transcribedText.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none_rounded,
              size: 58, color: accent.withOpacity(0.25)),
          const SizedBox(height: 14),
          Text(
            _speechAvailable
                ? 'Tap the mic to start speaking'
                : 'Initialising speech engine…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.38),
              fontSize: 17,
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Text(
        _transcribedText,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 22,
          height: 1.65,
          color: Colors.white,
          fontStyle: FontStyle.normal,
        ),
      ),
    );
  }
}