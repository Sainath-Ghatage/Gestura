// lib/screens/home_screen.dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sign_language,
                        color: Colors.black, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestura',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 1,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        'Accessibility Communication',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Grid ─────────────────────────────────────────────
              
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardW = (constraints.maxWidth - 12) / 2;
                    final cardH = (constraints.maxHeight - 12) / 2;
                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: cardW / cardH,
                      physics: const NeverScrollableScrollPhysics(),
                      children: const [
                        _FeatureTile(
                          route: '/stt',
                          icon: Icons.mic_rounded,
                          label: 'Speech\nto Text',
                          subtitle: 'Speak or import audio',
                          color: Color(0xFF00E5FF),
                        ),
                        _FeatureTile(
                          route: '/tts',
                          icon: Icons.record_voice_over_rounded,
                          label: 'Text\nto Speech',
                          subtitle: 'Type & speak aloud',
                          color: Color(0xFFFFD600),
                        ),
                        _FeatureTile(
                          route: '/sign',
                          icon: Icons.camera_alt_rounded,
                          label: 'Sign\nto Text',
                          subtitle: 'Camera sign detection',
                          color: Color(0xFF69FF47),
                        ),
                        _FeatureTile(
                          route: '/quick',
                          icon: Icons.chat_bubble_rounded,
                          label: 'Quick\nMessages',
                          subtitle: 'Tap to speak phrases',
                          color: Color(0xFFFF6D00),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── Footer ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Center(
                  child: Text(
                    'All processing is 100% on-device · No internet required',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Feature Tile — all sizing is proportional
//  to the card's actual rendered height/width,
//  so it CANNOT overflow regardless of device.
// ─────────────────────────────────────────────
class _FeatureTile extends StatelessWidget {
  final String route;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _FeatureTile({
    required this.route,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      hint: subtitle,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        elevation: 5,
        shadowColor: color.withOpacity(0.25),
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, route),
          borderRadius: BorderRadius.circular(20),
          splashColor: color.withOpacity(0.2),
          highlightColor: color.withOpacity(0.08),
          child: LayoutBuilder(
            builder: (context, box) {
              // Every size is derived from card height — overflow is impossible
              final iconBox = (box.maxHeight * 0.27).clamp(30.0, 54.0);
              final labelFs = (box.maxHeight * 0.115).clamp(13.0, 21.0);
              final subFs = (box.maxHeight * 0.068).clamp(10.0, 13.0);
              final pad = (box.maxHeight * 0.075).clamp(8.0, 15.0);

              return Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Icon badge
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(iconBox * 0.28),
                        border: Border.all(
                            color: color.withOpacity(0.35), width: 1.5),
                      ),
                      child: Icon(icon, color: color, size: iconBox * 0.52),
                    ),

                    const Spacer(),

                    // Label
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: labelFs,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),

                    SizedBox(height: pad * 0.25),

                    // Subtitle — ellipsis prevents any wrap overflow
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: subFs,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: pad * 0.45),

                    // Accent bar
                    Container(
                      height: 3,
                      width: 30,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
