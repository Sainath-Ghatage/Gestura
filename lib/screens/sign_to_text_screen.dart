// lib/screens/sign_to_text_screen.dart
//
// Works with tflite_flutter ^0.11.0
// - No .reshape() extension (removed in 0.11.x)
// - Uses nested List for input tensor
// - Uses InterpreterOptions() without deprecated fields

import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ASL class labels - order MUST match model output and train_asl_model.py
const List<String> _kLabels = [
  'A','B','C','D','E','F','G','H','I','J',
  'K','L','M','N','O','P','Q','R','S','T',
  'U','V','W','X','Y','Z','del','nothing','space',
];

const int    _kSize       = 224;   // model input: 224x224
const int    _kEveryN     = 8;     // infer every 8th frame (~3-4 fps)
const double _kThreshold  = 0.55;  // min confidence to show result
const int    _kHoldFrames = 18;    // frames to hold a sign to confirm (~1.5s)
const String _kAsset      = 'assets/models/asl_alphabet.tflite';


class SignToTextScreen extends StatefulWidget {
  const SignToTextScreen({super.key});

  @override
  State<SignToTextScreen> createState() => _SignToTextScreenState();
}

class _SignToTextScreenState extends State<SignToTextScreen>
    with WidgetsBindingObserver {

  // Camera
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  bool _isFront    = true;
  String _camErr   = '';

  // Model
  Interpreter? _interp;
  bool _modelReady   = false;
  bool _modelLoading = true;
  String _modelErr   = '';

  // Inference state
  bool   _inferring    = false;
  int    _frameCount   = 0;
  String _label        = '';
  double _confidence   = 0;

  // Word builder
  String _word            = '';
  String _lastLabel       = '';
  int    _holdCount       = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadModel();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _interp?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (s == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ---------- Model ----------

  Future<void> _loadModel() async {
    if (mounted) setState(() { _modelLoading = true; _modelErr = ''; });

    try {
      final opts = InterpreterOptions()..threads = 2;
      final interp = await Interpreter.fromAsset(_kAsset, options: opts);
      if (mounted) setState(() {
        _interp      = interp;
        _modelReady  = true;
        _modelLoading = false;
      });
    } catch (e1) {
      // Fallback: look in app documents folder
      try {
        final dir  = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/asl_alphabet.tflite');
        if (await file.exists()) {
          final opts  = InterpreterOptions()..threads = 2;
          final interp = await Interpreter.fromFile(file, options: opts);
          if (mounted) setState(() {
            _interp      = interp;
            _modelReady  = true;
            _modelLoading = false;
          });
        } else {
          throw Exception('Model not found in assets or documents directory.');
        }
      } catch (e2) {
        if (mounted) setState(() {
          _modelReady   = false;
          _modelLoading = false;
          _modelErr     = e2.toString();
        });
      }
    }
  }

  // ---------- Camera ----------

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    if (mounted) setState(() => _cameraReady = false);
    await c?.stopImageStream().catchError((_) {});
    await c?.dispose().catchError((_) {});
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      if (mounted) setState(() => _camErr = 'Cannot access camera: $e');
      return;
    }
    if (_cameras.isEmpty) {
      if (mounted) setState(() => _camErr = 'No cameras found.');
      return;
    }

    final desc = _isFront
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first)
        : _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first);

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

    setState(() { _controller = ctrl; _cameraReady = true; _camErr = ''; });

    if (_modelReady) _startStream();
  }

  void _startStream() {
    _controller?.startImageStream((CameraImage img) {
      _frameCount++;
      if (_frameCount % _kEveryN != 0 || _inferring) return;
      _runInference(img);
    });
  }

  Future<void> _flip() async {
    setState(() => _isFront = !_isFront);
    await _disposeCamera();
    await _initCamera();
  }

  // ---------- Inference ----------

  Future<void> _runInference(CameraImage img) async {
    if (_interp == null) return;
    setState(() => _inferring = true);

    try {
      // YUV420 -> Float32 flat array, done off the UI thread
      final flat = await compute(_yuv420ToFloat32, _YuvArgs(
        yPlane:       img.planes[0].bytes,
        uPlane:       img.planes[1].bytes,
        vPlane:       img.planes[2].bytes,
        uvRowStride:  img.planes[1].bytesPerRow,
        uvPixelStride: img.planes[1].bytesPerPixel ?? 2,
        srcW:  img.width,
        srcH:  img.height,
        outSz: _kSize,
      ));

      // Build [1, 224, 224, 3] as nested List (tflite_flutter 0.11.x API)
      final input = _buildInputTensor(flat);

      // Output buffer [1, 29]
      final output =
          List.generate(1, (_) => List<double>.filled(_kLabels.length, 0.0));

      _interp!.run(input, output);

      final scores = output[0];
      int   maxIdx = 0;
      double maxVal = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > maxVal) { maxVal = scores[i]; maxIdx = i; }
      }

      final detectedLabel = _kLabels[maxIdx];
      final detectedConf  = maxVal;

      if (mounted) {
        setState(() {
          if (detectedConf >= _kThreshold && detectedLabel != 'nothing') {
            _label      = detectedLabel;
            _confidence = detectedConf;

            // Hold-to-confirm logic
            if (detectedLabel == _lastLabel) {
              _holdCount++;
              if (_holdCount == _kHoldFrames) {
                if (detectedLabel == 'space') {
                  _word += ' ';
                } else if (detectedLabel == 'del') {
                  if (_word.isNotEmpty) _word = _word.substring(0, _word.length - 1);
                } else {
                  _word += detectedLabel;
                }
                _holdCount = 0;
              }
            } else {
              _lastLabel = detectedLabel;
              _holdCount = 0;
            }
          } else {
            _label      = '';
            _confidence = 0;
          }
          _inferring = false;
        });
      }
    } catch (e) {
      debugPrint('Inference error: $e');
      if (mounted) setState(() => _inferring = false);
    }
  }

  // Build [1, H, W, 3] nested List from flat Float32List
  List _buildInputTensor(Float32List flat) {
    final h = _kSize, w = _kSize;
    final tensor = List.generate(1, (_) =>
      List.generate(h, (y) =>
        List.generate(w, (x) {
          final base = (y * w + x) * 3;
          return [flat[base], flat[base + 1], flat[base + 2]];
        })
      )
    );
    return tensor;
  }

  // ---------- UI ----------

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
            await _disposeCamera();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: _StatusChip(
                loading: _modelLoading,
                ready:   _modelReady,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android_rounded, size: 26),
            onPressed: _cameraReady ? _flip : null,
            tooltip: 'Flip camera',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_camErr.isNotEmpty) return _buildError(_camErr);
    if (!_cameraReady || _controller == null) return _buildLoading();
    return _buildCameraView();
  }

  Widget _buildLoading() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: Color(0xFF69FF47)),
      SizedBox(height: 18),
      Text('Starting camera...',
          style: TextStyle(color: Colors.white70, fontSize: 17)),
    ]),
  );

  Widget _buildError(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_rounded, color: Colors.red, size: 64),
        const SizedBox(height: 18),
        Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _initCamera, child: const Text('Retry')),
      ]),
    ),
  );

  Widget _buildCameraView() {
    return Stack(fit: StackFit.expand, children: [

      // Camera preview
      CameraPreview(_controller!),

      // Bounding box overlay
      Positioned.fill(
        child: CustomPaint(
          painter: _BoxPainter(
            active: _label.isNotEmpty,
            progress: _lastLabel.isNotEmpty
                ? (_holdCount / _kHoldFrames).clamp(0.0, 1.0)
                : 0.0,
          ),
        ),
      ),

      // Live detection badge (top centre)
      Positioned(
        top: 16,
        left: 0, right: 0,
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

      // Model missing warning
      if (!_modelReady && !_modelLoading)
        Positioned(
          top: 60, left: 16, right: 16,
          child: _ModelMissingCard(),
        ),

      // Bottom panel
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: _BottomPanel(
          word:      _word,
          lastLabel: _lastLabel,
          holdCount: _holdCount,
          holdMax:   _kHoldFrames,
          onClear:   _label.isNotEmpty ? () => setState(() => _word = '') : null,
        ),
      ),
    ]);
  }
}


// ---- Helper widgets ----

class _StatusChip extends StatelessWidget {
  final bool loading, ready;
  const _StatusChip({required this.loading, required this.ready});

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.red;
    final label = loading ? 'Loading...' : ready ? 'Model OK' : 'No Model';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12,
              fontWeight: FontWeight.w700)),
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
        Text(label,
            style: const TextStyle(color: green, fontSize: 24,
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
          Text('ASL Model Not Found',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        const Text(
          '1. Train with train_asl_model.py\n'
          '2. Copy asl_model/asl_alphabet.tflite\n'
          '   into gestura/assets/models/\n'
          '3. Run: flutter clean && flutter run',
          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 6),
        Text('Dataset: kaggle.com/datasets/grassknoted/asl-alphabet',
            style: TextStyle(color: Colors.amber.shade300,
                fontSize: 11, fontStyle: FontStyle.italic)),
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
                word.isEmpty ? '...' : word,
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
                tooltip: 'Clear word',
              ),
          ]),

          if (lastLabel.isNotEmpty && holdCount > 0) ...[
            const SizedBox(height: 4),
            Text('Hold to confirm "$lastLabel"...',
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

          Text(
            'Hold each sign steady  |  ASL Alphabet  |  On-device inference',
            style: TextStyle(
                color: Colors.white.withOpacity(0.28), fontSize: 11),
          ),
        ],
      ),
    );
  }
}


// ---- Custom Painter ----

class _BoxPainter extends CustomPainter {
  final bool active;
  final double progress;
  const _BoxPainter({required this.active, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const green = Color(0xFF69FF47);
    final color = active ? green : Colors.white.withOpacity(0.3);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.5 : 1.5;

    final cx = size.width / 2;
    final cy = size.height * 0.40;
    const bw = 210.0, bh = 240.0;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: bw, height: bh);
    const cl = 28.0, r = 7.0;

    _drawCorner(canvas, paint, rect.topLeft,     cl, r, false, false);
    _drawCorner(canvas, paint, rect.topRight,    cl, r, true,  false);
    _drawCorner(canvas, paint, rect.bottomLeft,  cl, r, false, true);
    _drawCorner(canvas, paint, rect.bottomRight, cl, r, true,  true);

    if (progress > 0) {
      final arc = Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy), width: 52, height: 52),
        -1.5708,
        progress * 6.2832,
        false,
        arc,
      );
    }
  }

  void _drawCorner(Canvas c, Paint p, Offset o, double l, double r,
      bool flipX, bool flipY) {
    final sx = flipX ? -1.0 : 1.0;
    final sy = flipY ? -1.0 : 1.0;
    final path = Path();
    path.moveTo(o.dx,            o.dy + sy * l);
    path.lineTo(o.dx,            o.dy + sy * r);
    path.arcToPoint(
      Offset(o.dx + sx * r, o.dy),
      radius: const Radius.circular(7),
      clockwise: !(flipX ^ flipY),
    );
    path.lineTo(o.dx + sx * l,  o.dy);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.active != active || old.progress != progress;
}


// ---- Isolate helper: YUV420 -> Float32List ----

class _YuvArgs {
  final Uint8List yPlane, uPlane, vPlane;
  final int uvRowStride, uvPixelStride, srcW, srcH, outSz;
  const _YuvArgs({
    required this.yPlane, required this.uPlane, required this.vPlane,
    required this.uvRowStride, required this.uvPixelStride,
    required this.srcW, required this.srcH, required this.outSz,
  });
}

Float32List _yuv420ToFloat32(_YuvArgs a) {
  final out = Float32List(a.outSz * a.outSz * 3);
  final sx = a.srcW / a.outSz;
  final sy = a.srcH / a.outSz;
  int idx = 0;

  for (int ty = 0; ty < a.outSz; ty++) {
    for (int tx = 0; tx < a.outSz; tx++) {
      final px = (tx * sx).toInt().clamp(0, a.srcW - 1);
      final py = (ty * sy).toInt().clamp(0, a.srcH - 1);

      final yv = a.yPlane[py * a.srcW + px].toDouble();
      final uvIdx = (py >> 1) * a.uvRowStride + (px >> 1) * a.uvPixelStride;
      final uv  = uvIdx.clamp(0, a.uPlane.length - 1);
      final u   = a.uPlane[uv].toDouble() - 128;
      final v   = a.vPlane[uv].toDouble() - 128;

      out[idx++] = ((yv + 1.402 * v)              .clamp(0, 255)) / 255.0;
      out[idx++] = ((yv - 0.344136*u - 0.714136*v).clamp(0, 255)) / 255.0;
      out[idx++] = ((yv + 1.772 * u)              .clamp(0, 255)) / 255.0;
    }
  }
  return out;
}