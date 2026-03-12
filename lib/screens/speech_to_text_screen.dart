// lib/screens/speech_to_text_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';
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

  // ── File import state ─────────────────────────────────────────────────
  bool _isProcessingFile = false;
  String? _importedFileName;
  String? _importedFilePath;
  int? _importedFileSizeKb;
  String? _importedFileExt;

  // ── Processing stage label ────────────────────────────────────────────
  String _processingStage = '';

  // ── Demo note visibility ──────────────────────────────────────────────
  bool _showDemoNote = false;

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
      _importedFileName = null;
      _showDemoNote = false;
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

  Future<void> _pickFile() async {
    if (_isListening) await _stopListening();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac',
          'mp4', 'mkv', 'mov', 'avi', 'webm',
        ],
        allowMultiple: false,
      );
    } catch (e) {
      _showSnack('Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = file.path;

    // Read actual file size
    int? sizeKb;
    if (filePath != null) {
      try {
        final f = File(filePath);
        final bytes = await f.length();
        sizeKb = (bytes / 1024).round();
      } catch (_) {}
    }

    final ext = file.extension?.toLowerCase() ?? '';
    final isVideo = ['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext);

    setState(() {
      _isProcessingFile = true;
      _importedFileName = file.name;
      _importedFilePath = filePath;
      _importedFileSizeKb = sizeKb;
      _importedFileExt = ext;
      _transcribedText = '';
      _confidence = 0;
      _showDemoNote = false;
      _processingStage = isVideo ? 'Extracting audio track…' : 'Reading audio file…';
    });

    // Stage 1 — simulate audio extraction (video only)
    if (isVideo) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _processingStage = 'Decoding audio stream…');
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Stage 2 — simulate transcription
    if (!mounted) return;
    setState(() => _processingStage = 'Transcribing speech…');
    await Future.delayed(const Duration(seconds: 1, milliseconds: 400));

    // Stage 3 — produce demo result with honest labelling
    if (!mounted) return;
    setState(() {
      _transcribedText =
          '[Demo mode] On-device media transcription requires a bundled '
          'ML model (e.g. Whisper.cpp / Vosk). '
          'File loaded successfully: "${file.name}" '
          '(${sizeKb != null ? "${sizeKb}KB" : "size unknown"}, .$ext). '
          'Connect a transcription model here to get real output.';
      _isProcessingFile = false;
      _showDemoNote = true;
      _confidence = 0;
    });
  }

  void _clearText() => setState(() {
        _transcribedText = '';
        _importedFileName = null;
        _importedFilePath = null;
        _importedFileSizeKb = null;
        _importedFileExt = null;
        _confidence = 0;
        _showDemoNote = false;
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

              // ── Demo note banner ───────────────────────────────────
              if (_showDemoNote)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.amber.withOpacity(0.4), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'File import is in demo mode. '
                          'Integrate Whisper.cpp or Vosk for real transcription.',
                          style: TextStyle(
                              color: Colors.amber.shade200, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── File metadata chip (shown after picking) ───────────
              if (_importedFileName != null && !_isProcessingFile)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: accent.withOpacity(0.25), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isVideoExt(_importedFileExt)
                            ? Icons.videocam_rounded
                            : Icons.audio_file_rounded,
                        color: accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _importedFileName!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_importedFileSizeKb != null)
                        Text(
                          _importedFileSizeKb! >= 1024
                              ? '${(_importedFileSizeKb! / 1024).toStringAsFixed(1)} MB'
                              : '${_importedFileSizeKb!} KB',
                          style: TextStyle(
                              color: accent.withOpacity(0.7), fontSize: 12),
                        ),
                    ],
                  ),
                ),

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
                  child: _isProcessingFile
                      ? _buildProcessingView(theme)
                      : _buildTranscriptionView(theme, accent),
                ),
              ),

              const SizedBox(height: 14),

              // ── Confidence bar ─────────────────────────────────────
              if (_confidence > 0 && _transcribedText.isNotEmpty && !_showDemoNote)
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

              // ── Import button ─────────────────────────────────────
              OutlinedButton.icon(
                onPressed: _isProcessingFile ? null : _pickFile,
                icon: const Icon(Icons.upload_file_rounded, size: 24),
                label: const Text('Import Audio / Video File'),
              ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  bool _isVideoExt(String? ext) =>
      ['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext);

  Widget _buildProcessingView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 22),
        Text(
          _processingStage,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        if (_importedFileName != null)
          Text(
            _importedFileName!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
      ],
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
                ? 'Tap the mic to start speaking\nor import an audio/video file'
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
          color: _showDemoNote
              ? theme.colorScheme.onSurface.withOpacity(0.55)
              : Colors.white,
          fontStyle:
              _showDemoNote ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}