import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const int    _kSize       = 224;          // model input WxH
const int    _kEveryN     = 6;            // infer every N frames
const double _kThreshold  = 0.60;         // Minimum confidence
const int    _kHoldFrames = 15;           // frames to hold before confirming
const String _kAsset      = 'assets/models/model_unquant.tflite';
const String _kLabelsFile = 'assets/models/labels.txt';

// ─────────────────────────────────────────────────────────────────────────────

class SignToTextScreen extends StatefulWidget {
  const SignToTextScreen({super.key});
  @override
  State<SignToTextScreen> createState() => _SignToTextScreenState();
}

class _SignToTextScreenState extends State<SignToTextScreen>
    with WidgetsBindingObserver {

  // Camera state
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  bool _camReady = false;
  bool _isFront  = true;
  String _camErr  = '';

  // Model & Labels state
  Interpreter? _interp;
  List<String> _labels = [];
  bool _modelReady   = false;
  bool _modelLoading = true;
  String _modelErr   = '';

  // Inference state
  bool   _inferring  = false;
  int    _frameCount = 0;
  String _label      = '';
  double _confidence = 0;
  String _debugMsg   = 'Initialising…';

  // Word builder
  String _word      = '';
  String _lastLabel = '';
  int    _holdCount = 0;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSystem();
  }

  Future<void> _initSystem() async {
    await _loadLabels();
    await _loadModel();
    await _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndDisposeCamera();
    final i = _interp;
    _interp = null;
    i?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) _stopAndDisposeCamera();
    if (s == AppLifecycleState.resumed)  _initCamera();
  }

  // ── Model & Labels ──────────────────────────────────────────────────────────

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString(_kLabelsFile);
      // Split by line, trim whitespace, remove empty lines
      List<String> rawLabels = labelsData.split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      
      // Teachable Machine labels usually look like "0 ClassName". Strip the number.
      _labels = rawLabels.map((s) => s.replaceFirst(RegExp(r'^\d+\s+'), '')).toList();
      _dbg('Loaded ${_labels.length} labels');
    } catch (e) {
      _dbg('Failed to load labels.txt: $e');
    }
  }

  Future<void> _loadModel() async {
    if (mounted) setState(() { _modelLoading = true; _modelErr  = ''; });
    _dbg('Loading model from assets…');

    try {
      final opts = InterpreterOptions()..threads = 2;
      final interp = await Interpreter.fromAsset(_kAsset, options: opts);

      if (mounted) setState(() {
        _interp      = interp;
        _modelReady  = true;
        _modelLoading = false;
        _debugMsg    = 'Model loaded ✓  Starting camera…';
      });

      if (_camReady && _ctrl != null) _startStream();
    } catch (e) {
      _dbg('Model load FAILED: $e');
      if (mounted) setState(() {
        _modelReady   = false;
        _modelLoading = false;
        _modelErr     = e.toString();
        _debugMsg     = 'Model ERROR: $e';
      });
    }
  }

  // ── Camera ──────────────────────────────────────────────────────────────────

  Future<void> _stopAndDisposeCamera() async {
    final c = _ctrl;
    _ctrl = null;
    if (mounted) setState(() => _camReady = false);
    try { await c?.stopImageStream(); } catch (_) {}
    try { await c?.dispose(); }        catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      if (mounted) setState(() => _camErr = 'Camera list error: $e');
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _camErr = 'No cameras found.');
      return;
    }

    final desc = _isFront
        ? _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => _cameras.first)
        : _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => _cameras.first);

    final ctrl = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      ctrl.dispose();
      if (mounted) setState(() => _camErr = e.description ?? e.code);
      return;
    }

    if (!mounted) { ctrl.dispose(); return; }

    setState(() {
      _ctrl     = ctrl;
      _camReady = true;
      _camErr   = '';
    });

    if (_modelReady) _startStream();
  }

  void _startStream() {
    _dbg('Image stream started');
    _ctrl?.startImageStream((CameraImage img) {
      _frameCount++;
      if (_frameCount % _kEveryN != 0 || _inferring) return;
      _runInference(img);
    });
  }

  Future<void> _flip() async {
    setState(() => _isFront = !_isFront);
    await _stopAndDisposeCamera();
    await _initCamera();
  }

  // ── Inference ────────────────────────────────────────────────────────────────

  void _runInference(CameraImage cameraFrame) {
    final interp = _interp;
    if (interp == null || _labels.isEmpty) return;
    _inferring = true;

    try {
      // 1. YUV420 → img.Image
      img.Image rgbImage = _convertYUV420(cameraFrame);

      // 2. Rotate & Mirror (Critical for Teachable Machine models)
      rgbImage = img.copyRotate(rgbImage, angle: 90);
      if (_isFront) {
        rgbImage = img.flipHorizontal(rgbImage);
      }

      // 3. Resize
      final resized = img.copyResize(rgbImage, width: _kSize, height: _kSize);

      // 4. Create precise 4D nested list [1, 224, 224, 3] expected by TFLite
      final input = List.generate(1, (_) =>
        List.generate(_kSize, (y) =>
          List.generate(_kSize, (x) {
            final p = resized.getPixelSafe(x, y);
            return [
              (p.r / 127.5) - 1.0,
              (p.g / 127.5) - 1.0,
              (p.b / 127.5) - 1.0
            ];
          })
        )
      );

      // 5. Run Inference dynamically scaled to label count
      final output = List.generate(1, (_) => List<double>.filled(_labels.length, 0.0));
      interp.run(input, output);

      final scores = output[0];

      // Find top result
      int    maxIdx = 0;
      double maxVal = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > maxVal) { maxVal = scores[i]; maxIdx = i; }
      }

      final topLabel = _labels[maxIdx];
      final topConf  = maxVal;

      if (_frameCount % 30 == 0) {
        debugPrint('▶ $topLabel ${(topConf*100).toStringAsFixed(1)}%');
      }

      if (mounted) setState(() {
        _debugMsg = '$topLabel  ${(topConf * 100).toStringAsFixed(1)}%';

        if (topConf >= _kThreshold && topLabel.toLowerCase() != 'nothing' && topLabel.toLowerCase() != 'background') {
          _label      = topLabel;
          _confidence = topConf;

          if (topLabel == _lastLabel) {
            _holdCount++;
            if (_holdCount == _kHoldFrames) {
              if (topLabel.toLowerCase() == 'space') {
                _word += ' ';
              } else if (topLabel.toLowerCase() == 'del') {
                if (_word.isNotEmpty) _word = _word.substring(0, _word.length - 1);
              } else {
                _word += topLabel;
              }
              _holdCount = 0;
            }
          } else {
            _lastLabel = topLabel;
            _holdCount = 0;
          }
        } else {
          _label      = '';
          _confidence = 0;
        }
      });

    } catch (e, st) {
      debugPrint('INFERENCE ERROR: $e\n$st');
      if (mounted) setState(() => _debugMsg = 'Inference error: $e');
    } finally {
      _inferring = false;
    }
  }

  // ── Image helpers ────────────────────────────────────────────────────────────

  img.Image _convertYUV420(CameraImage c) {
    final w = c.width, h = c.height;
    final uvRowStride   = c.planes[1].bytesPerRow;
    final uvPixelStride = c.planes[1].bytesPerPixel!;
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      final pY  = y * c.planes[0].bytesPerRow;
      final pUV = (y >> 1) * uvRowStride;
      for (int x = 0; x < w; x++) {
        final uvOff = pUV + (x >> 1) * uvPixelStride;
        if (pY + x >= c.planes[0].bytes.length ||
            uvOff  >= c.planes[1].bytes.length ||
            uvOff  >= c.planes[2].bytes.length) continue;
        final yp = c.planes[0].bytes[pY + x];
        final up = c.planes[1].bytes[uvOff];
        final vp = c.planes[2].bytes[uvOff];
        final r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        final g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
        final b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  // ── Debug helper ─────────────────────────────────────────────────────────────

  void _dbg(String msg) {
    debugPrint('[SignToText] $msg');
    if (mounted) setState(() => _debugMsg = msg);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Sign to Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            await _stopAndDisposeCamera();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: _StatusChip(loading: _modelLoading, ready: _modelReady)),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android_rounded, size: 26),
            onPressed: _camReady ? _flip : null,
            tooltip: 'Flip camera',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_camErr.isNotEmpty) return _buildError(_camErr);
    if (!_camReady || _ctrl == null) return _buildLoading();
    return _buildCameraView();
  }

  Widget _buildLoading() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: Color(0xFF69FF47)),
      SizedBox(height: 18),
      Text('Starting camera…', style: TextStyle(color: Colors.white70, fontSize: 17)),
    ]),
  );

  Widget _buildError(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_rounded, color: Colors.red, size: 64),
        const SizedBox(height: 18),
        Text(msg, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _initCamera, child: const Text('Retry')),
      ]),
    ),
  );

  Widget _buildCameraView() {
    return Stack(fit: StackFit.expand, children: [

      // Camera preview
      CameraPreview(_ctrl!),

      // Corner guide box
      Positioned.fill(
        child: CustomPaint(
          painter: _BoxPainter(
            active:   _label.isNotEmpty,
            progress: _lastLabel.isNotEmpty
                ? (_holdCount / _kHoldFrames).clamp(0.0, 1.0) : 0.0,
          ),
        ),
      ),

      // ── DEBUG PANEL (top) ──────────────────────────────────────────────────
      Positioned(
        top: 8, left: 8, right: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Text(
            _debugMsg,
            style: const TextStyle(color: Colors.yellowAccent, fontSize: 12,
                fontFamily: 'monospace'),
          ),
        ),
      ),

      // Detection badge (below debug panel)
      Positioned(
        top: 52, left: 0, right: 0,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _label.isNotEmpty
                ? _DetectionBadge(key: ValueKey(_label),
                    label: _label, confidence: _confidence)
                : _IdleBadge(key: const ValueKey('idle'),
                    modelReady: _modelReady),
          ),
        ),
      ),

      // Model error card
      if (!_modelReady && !_modelLoading)
        Positioned(
          top: 90, left: 16, right: 16,
          child: _ModelMissingCard(error: _modelErr),
        ),

      // Bottom word panel
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: _BottomPanel(
          word:      _word,
          lastLabel: _lastLabel,
          holdCount: _holdCount,
          holdMax:   _kHoldFrames,
          onClear:   _word.isNotEmpty ? () => setState(() { _word = ''; }) : null,
        ),
      ),
    ]);
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool loading, ready;
  const _StatusChip({required this.loading, required this.ready});

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.red;
    final label = loading ? 'Loading…' : ready ? 'Model OK' : 'No Model';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _DetectionBadge extends StatelessWidget {
  final String label;
  final double confidence;
  const _DetectionBadge({super.key, required this.label, required this.confidence});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF69FF47);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: green.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: green, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: green, fontSize: 26,
            fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(width: 10),
        Text('${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: Colors.white.withOpacity(0.6),
                fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _IdleBadge extends StatelessWidget {
  final bool modelReady;
  const _IdleBadge({super.key, required this.modelReady});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: modelReady ? const Color(0xFF69FF47) : Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          modelReady ? 'Show a sign to the camera' : 'Model not loaded',
          style: const TextStyle(color: Colors.white70,
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }
}

class _ModelMissingCard extends StatelessWidget {
  final String error;
  const _ModelMissingCard({this.error = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
          SizedBox(width: 8),
          Text('ASL Model Load Failed',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11, height: 1.5)),
        ],
        const SizedBox(height: 8),
        const Text(
          'Ensure model_unquant.tflite and labels.txt\n'
          'are inside gestura/assets/models/ directory\n'
          'and listed under flutter › assets in pubspec.yaml.',
          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.6),
        ),
      ]),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final String word, lastLabel;
  final int holdCount, holdMax;
  final VoidCallback? onClear;

  const _BottomPanel({
    required this.word,
    required this.lastLabel,
    required this.holdCount,
    required this.holdMax,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF69FF47);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.95), Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Word: ',
                style: TextStyle(color: Colors.white38,
                    fontSize: 15, fontWeight: FontWeight.w500)),
            Expanded(
              child: Text(
                word.isEmpty ? '…' : word,
                style: const TextStyle(color: green, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: 3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (word.isNotEmpty && onClear != null)
              IconButton(
                icon: const Icon(Icons.backspace_outlined,
                    color: Colors.white38, size: 20),
                onPressed: onClear,
                tooltip: 'Clear',
              ),
          ]),

          if (lastLabel.isNotEmpty && holdCount > 0) ...[
            const SizedBox(height: 4),
            Text('Hold "$lastLabel" to confirm…',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 12)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: holdCount / holdMax,
                backgroundColor: green.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(green),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
          ],

          Text('Hold each sign steady  |  ASL Alphabet  |  On-device',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.28), fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Corner-box overlay ────────────────────────────────────────────────────────

class _BoxPainter extends CustomPainter {
  final bool   active;
  final double progress;
  const _BoxPainter({required this.active, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const green = Color(0xFF69FF47);
    final color = active ? green : Colors.white.withOpacity(0.35);
    final paint = Paint()
      ..color      = color
      ..style      = PaintingStyle.stroke
      ..strokeWidth = active ? 2.5 : 1.5;

    final cx   = size.width / 2;
    final cy   = size.height * 0.40;
    const bw   = 220.0;
    const bh   = 250.0;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh);
    const cl = 28.0, r = 7.0;

    _corner(canvas, paint, rect.topLeft,     cl, r, false, false);
    _corner(canvas, paint, rect.topRight,    cl, r, true,  false);
    _corner(canvas, paint, rect.bottomLeft,  cl, r, false, true);
    _corner(canvas, paint, rect.bottomRight, cl, r, true,  true);

    if (progress > 0) {
      final arc = Paint()
        ..color = green ..style = PaintingStyle.stroke
        ..strokeWidth = 3 ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy), width: 52, height: 52),
        -1.5708, progress * 6.2832, false, arc,
      );
    }
  }

  void _corner(Canvas c, Paint p, Offset o,
               double l, double r, bool fx, bool fy) {
    final sx = fx ? -1.0 : 1.0;
    final sy = fy ? -1.0 : 1.0;
    final path = Path()
      ..moveTo(o.dx,           o.dy + sy * l)
      ..lineTo(o.dx,           o.dy + sy * r)
      ..arcToPoint(Offset(o.dx + sx * r, o.dy),
          radius: const Radius.circular(7), clockwise: !(fx ^ fy))
      ..lineTo(o.dx + sx * l,  o.dy);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.active != active || old.progress != progress;
}