// lib/screens/text_to_speech_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

class TextToSpeechScreen extends StatefulWidget {
  const TextToSpeechScreen({super.key});

  @override
  State<TextToSpeechScreen> createState() => _TextToSpeechScreenState();
}

class _TextToSpeechScreenState extends State<TextToSpeechScreen> {
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isSpeaking = false;
  bool _isExporting = false;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    _tts.stop();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(_volume);
    await _tts.setPitch(_pitch);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) {
        setState(() => _isSpeaking = false);
        _showSnack('TTS error: $msg');
      }
    });
  }

  Future<void> _speak() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('Please type something first.');
      return;
    }
    _focusNode.unfocus();
    if (_isSpeaking) {
      await _tts.stop();
    } else {
      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);
      await _tts.speak(text);
    }
  }

  Future<void> _exportAudio() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('Please type some text before exporting.');
      return;
    }
    if (_isSpeaking) await _tts.stop();

    setState(() => _isExporting = true);
    _focusNode.unfocus();

    try {
      // Try to get a writable external dir first, fall back to app docs
      Directory? saveDir;
      try {
        final ext = await getExternalStorageDirectory();
        saveDir = ext;
      } catch (_) {
        saveDir = await getApplicationDocumentsDirectory();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${saveDir!.path}/gestura_tts_$timestamp.wav';

      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);

      // synthesizeToFile is supported on Android with most TTS engines
      final result = await _tts.synthesizeToFile(text, filePath);

      if (mounted) {
        if (result == 1) {
          _showSnack('✅  Saved to: $filePath', duration: const Duration(seconds: 5));
        } else {
          // Fallback: some engines return 0 but still write the file
          final file = File(filePath);
          if (await file.exists()) {
            _showSnack('✅  Saved to: $filePath', duration: const Duration(seconds: 5));
          } else {
            _showSnack('⚠️  Export not supported by this TTS engine.');
          }
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSnack(String msg, {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = Color(0xFFFFD600);

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Text → Speech'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () async {
              await _tts.stop();
              if (mounted) Navigator.of(context).pop();
            },
          ),
          actions: [
            if (_textController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _textController.clear();
                  setState(() {});
                },
                tooltip: 'Clear',
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Text Input ───────────────────────────────────────────
                TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  onChanged: (_) => setState(() {}),
                  maxLines: 6,
                  minLines: 4,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 22),
                  decoration: const InputDecoration(
                    labelText: 'Type your message…',
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Big SPEAK Button ─────────────────────────────────────
                Semantics(
                  button: true,
                  label: _isSpeaking ? 'Stop speaking' : 'Speak text aloud',
                  child: ElevatedButton.icon(
                    onPressed: _speak,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSpeaking ? Colors.red.shade700 : accentColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 80),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: Icon(
                      _isSpeaking
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 40,
                    ),
                    label: Text(
                      _isSpeaking ? 'STOP' : 'SPEAK',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Export Button ────────────────────────────────────────
                OutlinedButton.icon(
                  onPressed: _isExporting ? null : _exportAudio,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: const BorderSide(color: accentColor, width: 2),
                    minimumSize: const Size(double.infinity, 64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.download_rounded, size: 28),
                  label: Text(
                    _isExporting ? 'Saving…' : 'Export as Audio File',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Voice Settings ───────────────────────────────────────
                _SectionHeader(label: 'Voice Settings', color: accentColor),
                const SizedBox(height: 16),

                _SliderRow(
                  label: 'Speed',
                  icon: Icons.speed_rounded,
                  value: _speechRate,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  accentColor: accentColor,
                  displayValue: '${(_speechRate * 100).round()}%',
                  onChanged: (v) => setState(() => _speechRate = v),
                ),

                _SliderRow(
                  label: 'Pitch',
                  icon: Icons.music_note_rounded,
                  value: _pitch,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  accentColor: accentColor,
                  displayValue: _pitch.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _pitch = v),
                ),

                _SliderRow(
                  label: 'Volume',
                  icon: Icons.volume_up_rounded,
                  value: _volume,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  accentColor: accentColor,
                  displayValue: '${(_volume * 100).round()}%',
                  onChanged: (v) => setState(() => _volume = v),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 22, color: color,
            margin: const EdgeInsets.only(right: 10)),
        Text(label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color accentColor;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.accentColor,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 28),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accentColor,
                thumbColor: accentColor,
                inactiveTrackColor: accentColor.withOpacity(0.2),
                overlayColor: accentColor.withOpacity(0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              displayValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: accentColor, fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}