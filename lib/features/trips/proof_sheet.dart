import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../widgets/workspace.dart';

import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../state/app_state.dart';

Future<bool?> showProofSheet(
  BuildContext context,
  String stopId, {
  bool requiredForDelivery = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      ProofSheet(stopId: stopId, requiredForDelivery: requiredForDelivery),
);

class ProofSheet extends StatefulWidget {
  final String stopId;
  final bool requiredForDelivery;
  const ProofSheet({
    super.key,
    required this.stopId,
    this.requiredForDelivery = false,
  });
  @override
  State<ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<ProofSheet> {
  bool _busy = false;
  String? _error, _key;
  Uint8List? _draft;
  String _kind = 'photo';
  List<Map<String, dynamic>> _saved = [];
  bool _started = false;
  bool _loading = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AppScope.of(context).repository.proofs(widget.stopId);
      if (mounted) setState(() => _saved = data);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _photo(ImageSource source) async {
    try {
      AppScope.of(context).requireOnlineAction();
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024)
        throw StateError('Select an image smaller than 5 MB.');
      if (mounted)
        setState(() {
          _draft = bytes;
          _kind = 'photo';
          _key = AppState.newOperationKey();
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    }
  }

  Future<void> _signature() async {
    try {
      AppScope.of(context).requireOnlineAction();
      final bytes = await showDialog<Uint8List>(
        context: context,
        builder: (_) => const SignatureDialog(),
      );
      if (bytes != null && mounted)
        setState(() {
          _draft = bytes;
          _kind = 'signature';
          _key = AppState.newOperationKey();
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    }
  }

  Future<void> _upload() async {
    final draft = _draft, key = _key;
    if (draft == null || key == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      AppScope.of(context).requireOnlineAction();
      await AppScope.of(context).repository
          .uploadProof(widget.stopId, draft, _kind, key);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _key = null;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(String id) async {
    try {
      final bytes = await AppScope.of(context).repository
          .proofBytes(widget.stopId, id);
      if (mounted)
        await showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.memory(bytes),
            ),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (AppScope.of(context).isOffline)
              const FeedbackStrip(
                'Offline - proof capture and uploads require an internet connection.',
                warning: true,
              ),
            Text(
              widget.requiredForDelivery
                  ? 'Proof of Delivery (POD)'
                  : 'Delivery proofs',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Up to three photos and one signature per stop. Proofs are saved only after server confirmation.',
            ),
            if (widget.requiredForDelivery)
              const Text(
                'Submit a photo or signature before continuing to Confirm delivery.',
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || AppScope.of(context).isOffline
                      ? null
                      : () => _photo(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || AppScope.of(context).isOffline
                      ? null
                      : () => _photo(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photo'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || AppScope.of(context).isOffline
                      ? null
                      : _signature,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Sign'),
                ),
              ],
            ),
            if (_draft != null) ...[
              const SizedBox(height: 16),
              Text('Ready to upload', style: T.bodyBold),
              const SizedBox(height: 8),
              Image.memory(_draft!, height: 180),
              FilledButton(
                onPressed: _busy || AppScope.of(context).isOffline
                    ? null
                    : _upload,
                child: Text(_busy ? 'Uploading...' : 'Upload proof'),
              ),
            ],
            if (_error != null) FeedbackStrip(_error!),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text('Saved proofs', style: T.bodyBold),
            if (_loading)
              Semantics(
                liveRegion: true,
                child: Text('Checking saved proofs...', style: T.small),
              ),
            if (!_loading && _saved.isEmpty && _error == null)
              Text('No proof uploaded yet.', style: T.small),
            for (final proof in _saved)
              ListTile(
                title: Text('${proof['kind']} - ${proof['createdAt']}'),
                trailing: const Icon(Icons.visibility),
                onTap: _busy || AppScope.of(context).isOffline
                    ? null
                    : () => _view(proof['id'] as String),
              ),
            TextButton(
              onPressed: _busy || _loading || AppScope.of(context).isOffline
                  ? null
                  : _load,
              child: const Text('Refresh saved proofs'),
            ),
            if (widget.requiredForDelivery)
              FilledButton(
                onPressed:
                    _busy ||
                        _loading ||
                        _error != null ||
                        _saved.isEmpty ||
                        _draft != null ||
                        !AppScope.of(context).canPerformActions
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Continue to Confirm delivery'),
              ),
          ],
        ),
      ),
    ),
  );
}

class SignatureDialog extends StatefulWidget {
  const SignatureDialog({super.key});
  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  final List<Offset?> _points = [];
  Future<void> _save() async {
    if (_points.whereType<Offset>().length < 3) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    _SignaturePainter(_points).paint(canvas, const Size(300, 160));
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 320);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (mounted && bytes != null)
      Navigator.of(context).pop(bytes.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Recipient signature'),
    content: SizedBox(
      width: 300,
      height: 160,
      child: GestureDetector(
        onPanStart: (e) => setState(() => _points.add(e.localPosition)),
        onPanUpdate: (e) => setState(() => _points.add(e.localPosition)),
        onPanEnd: (_) => setState(() => _points.add(null)),
        child: CustomPaint(
          key: const Key('signature-canvas'),
          painter: _SignaturePainter(_points),
          child: const SizedBox.expand(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(_points.clear),
        child: const Text('Clear'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _points.whereType<Offset>().length < 3 ? null : _save,
        child: const Text('Use signature'),
      ),
    ],
  );
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 1; i < points.length; i++) {
      if (points[i - 1] != null && points[i] != null)
        canvas.drawLine(points[i - 1]!, points[i]!, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
