import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ─────────────────────────────────────────────
//  Data model for a quick phrase tile
// ─────────────────────────────────────────────
class _Phrase {
  final String text;
  final String emoji;
  final Color color;

  const _Phrase({required this.text, required this.emoji, required this.color});
}

const List<_Phrase> _phrases = [
  // Essential
  _Phrase(text: 'Hello', emoji: '👋', color: Color(0xFF00E5FF)),
  _Phrase(text: 'Thank you', emoji: '🙏', color: Color(0xFF69FF47)),
  _Phrase(text: 'Please help me', emoji: '🆘', color: Color(0xFFFF1744)),
  _Phrase(text: 'Emergency!', emoji: '🚨', color: Color(0xFFFF6D00)),

  // Needs
  _Phrase(text: 'I need water', emoji: '💧', color: Color(0xFF40C4FF)),
  _Phrase(text: 'I need food', emoji: '🍽️', color: Color(0xFFFFD600)),
  _Phrase(text: 'I need a doctor', emoji: '🏥', color: Color(0xFFFF5252)),
  _Phrase(text: 'I need a restroom', emoji: '🚻', color: Color(0xFFB2FF59)),

  // Responses
  _Phrase(text: 'Yes', emoji: '✅', color: Color(0xFF69FF47)),
  _Phrase(text: 'No', emoji: '❌', color: Color(0xFFFF5252)),
  _Phrase(text: 'I understand', emoji: '👍', color: Color(0xFF00E5FF)),
  _Phrase(text: 'Please repeat', emoji: '🔁', color: Color(0xFFEA80FC)),

  // Social
  _Phrase(text: 'Good morning', emoji: '🌅', color: Color(0xFFFFD600)),
  _Phrase(text: 'Good night', emoji: '🌙', color: Color(0xFF536DFE)),
  _Phrase(text: 'How are you?', emoji: '🤔', color: Color(0xFF00E5FF)),
  _Phrase(text: 'I am fine', emoji: '😊', color: Color(0xFF69FF47)),

  // Pain / Medical
  _Phrase(text: 'I am in pain', emoji: '😣', color: Color(0xFFFF5252)),
  _Phrase(text: 'I feel dizzy', emoji: '😵', color: Color(0xFFFF6D00)),
  _Phrase(text: 'Call an ambulance', emoji: '🚑', color: Color(0xFFFF1744)),
  _Phrase(text: 'My medication', emoji: '💊', color: Color(0xFFEA80FC)),

  // Navigation
  _Phrase(text: 'Where is the exit?', emoji: '🚪', color: Color(0xFFFFD600)),
  _Phrase(text: 'I am lost', emoji: '📍', color: Color(0xFFFF6D00)),
  _Phrase(text: 'Please call a taxi', emoji: '🚕', color: Color(0xFFFFD600)),
  _Phrase(text: 'Take me home', emoji: '🏠', color: Color(0xFF00E5FF)),
];

class QuickSignsScreen extends StatefulWidget {
  const QuickSignsScreen({super.key});

  @override
  State<QuickSignsScreen> createState() => _QuickSignsScreenState();
}

class _QuickSignsScreenState extends State<QuickSignsScreen> {
  final FlutterTts _tts = FlutterTts();
  String? _lastSpoken;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(_Phrase phrase) async {
    // Haptic feedback for extra accessibility
    await HapticFeedback.mediumImpact();

    if (_isSpeaking) await _tts.stop();

    setState(() => _lastSpoken = phrase.text);
    await _tts.speak(phrase.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = Color(0xFFFF6D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Signs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            _tts.stop();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        children: [
          // ── Last spoken banner ───────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _lastSpoken != null ? 70 : 0,
            color: accentColor.withOpacity(0.12),
            child: _lastSpoken != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(
                          _isSpeaking
                              ? Icons.volume_up_rounded
                              : Icons.check_circle_rounded,
                          color: accentColor,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _lastSpoken!,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _isSpeaking ? 'Speaking…' : 'Spoken ✓',
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),

          // ── Phrase Grid ──────────────────────────────────────────────
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.35,
              ),
              itemCount: _phrases.length,
              itemBuilder: (context, index) {
                final phrase = _phrases[index];
                final isActive = _lastSpoken == phrase.text && _isSpeaking;

                return Semantics(
                  button: true,
                  label: phrase.text,
                  hint: 'Tap to speak aloud',
                  child: AnimatedScale(
                    scale: isActive ? 0.96 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Material(
                      color: isActive
                          ? phrase.color.withOpacity(0.25)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      elevation: isActive ? 2 : 5,
                      shadowColor: phrase.color.withOpacity(0.25),
                      child: InkWell(
                        onTap: () => _speak(phrase),
                        borderRadius: BorderRadius.circular(18),
                        splashColor: phrase.color.withOpacity(0.25),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive
                                  ? phrase.color
                                  : phrase.color.withOpacity(0.25),
                              width: isActive ? 2.5 : 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                phrase.emoji,
                                style: const TextStyle(fontSize: 32),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                phrase.text,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isActive ? phrase.color : Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Footer hint ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Text(
              'Tap any tile to speak instantly · No internet required',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}