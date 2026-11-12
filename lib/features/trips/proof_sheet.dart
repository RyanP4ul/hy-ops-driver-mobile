import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/workspace.dart';

Future<bool?> showProofSheet(
  BuildContext context,
  String stopId, {
  bool requiredForDelivery = false,
  String? orderLabel,
  String? customer,
  bool readOnly = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ProofSheet(
    stopId: stopId,
    requiredForDelivery: requiredForDelivery,
    orderLabel: orderLabel,
    customer: customer,
    readOnly: readOnly,
  ),
);

class ProofSheet extends StatefulWidget {
  final String stopId;
  final bool requiredForDelivery;
  final String? orderLabel;
  final String? customer;
  final bool readOnly;

  const ProofSheet({
    super.key,
    required this.stopId,
    this.requiredForDelivery = false,
    this.orderLabel,
    this.customer,
    this.readOnly = false,
  });

  @override
  State<ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<ProofSheet> {
  bool _busy = false;
  String? _error, _key;
  Uint8List? _draft;
  List<Map<String, dynamic>> _saved = [];
  bool _started = false;
  bool _loading = true;
  StreamSubscription<void>? _changes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final repository = AppScope.of(context).repository;
      _changes = repository.changes.listen((_) async {
        try {
          final saved = await repository.saved(
            () => repository.proofs(widget.stopId),
          );
          if (mounted) setState(() => _saved = saved);
        } catch (_) {
          /* Keep the current draft and explain errors on explicit load. */
        }
      });
      _load();
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
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
      AppScope.of(context).requireSavedAction();
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('Select an image smaller than 5 MB.');
      }
      if (mounted) {
        setState(() {
          _draft = bytes;
          _key = AppState.newOperationKey();
          _error = null;
        });
      }
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
      AppScope.of(context).requireSavedAction();
      await AppScope.of(
        context,
      ).repository.uploadProof(widget.stopId, draft, 'photo', key);
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
      final bytes = await AppScope.of(
        context,
      ).repository.proofBytes(widget.stopId, id);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Ic.close),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    }
  }

  String _formatProofTitle(Map<String, dynamic> proof) {
    const label = 'Photo';
    final rawTime = proof['createdAt']?.toString() ?? '';
    final parsed = DateTime.tryParse(rawTime);
    if (parsed == null) return rawTime.isEmpty ? label : '$label · $rawTime';
    return '$label · ${fmtWhen(parsed.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final subtitleParts = [
      if (widget.orderLabel != null && widget.orderLabel!.isNotEmpty)
        widget.orderLabel!,
      if (widget.customer != null && widget.customer!.isNotEmpty)
        widget.customer!,
    ];

    return PopScope(
      canPop: !_busy,
      child: AppBottomSheet(
        title: widget.requiredForDelivery
            ? 'Proof of Delivery (POD)'
            : 'Delivery proofs',
        subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
        canClose: !_busy,
        fixedHeightFraction: 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.isOffline) ...[
              FeedbackStrip(
                s.offlineActionRestriction ??
                    'Offline - save proof on this device. Upload resumes automatically when connected.',
                warning: true,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              widget.readOnly
                  ? 'This stop is already recorded. Saved proofs below are read-only.'
                  : widget.requiredForDelivery
                  ? 'Submit a photo before continuing to Confirm delivery. Up to three photos per stop.'
                  : 'Up to three photos per stop. Saved proof stays on this device until the server accepts the upload.',
              style: T.smallFor(c),
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, bounds) {
                  final compact =
                      bounds.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19;
                  final buttons = [
                    OutlinedButton.icon(
                      onPressed: _busy || !s.canSaveActions
                          ? null
                          : () => _photo(ImageSource.camera),
                      icon: const Icon(Ic.camera, size: 18),
                      label: const Text('Camera'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !s.canSaveActions
                          ? null
                          : () => _photo(ImageSource.gallery),
                      icon: const Icon(Ic.image, size: 18),
                      label: const Text('Choose photo'),
                    ),
                  ];
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < buttons.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          buttons[i],
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: buttons[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
            if (_draft != null) ...[
              const SizedBox(height: 16),
              Panel(
                color: c.surfaceSubtle,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Photo ready to save',
                            style: T.bodyBoldFor(c),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _draft = null;
                                  _key = null;
                                }),
                          icon: const Icon(Ic.close, size: 16),
                          label: const Text('Discard'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 36),
                            foregroundColor: c.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.white,
                        height: 180,
                        child: Image.memory(_draft!, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BigButton(
                      _busy ? 'Saving...' : 'Save proof',
                      busy: _busy,
                      onTap: _busy || !s.canSaveActions ? null : _upload,
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              FeedbackStrip(_error!),
            ],
            const SizedBox(height: 20),
            Divider(height: 1, color: c.line),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved proofs and pending uploads',
                    style: T.bodyBoldFor(c),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || _loading ? null : _load,
                  icon: const Icon(Ic.refresh, size: 15),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Ic.clock, size: 16, color: c.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          'Checking saved proofs...',
                          style: T.smallFor(c),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_loading && _saved.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No proof uploaded yet.', style: T.smallFor(c)),
              ),
            for (final proof in _saved) ...[
              const SizedBox(height: 8),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                onTap:
                    _busy || (s.isOffline && proof['availableOffline'] != true)
                    ? null
                    : () => _view(proof['id'] as String),
                child: Row(
                  children: [
                    IconTile(
                      Ic.camera,
                      bg: c.surfaceSubtle,
                      fg: c.primary,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatProofTitle(proof),
                            style: T.bodyBoldFor(c).copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.isOffline && proof['availableOffline'] != true
                                ? 'Photo not downloaded. Connect to view it.'
                                : proof['availableOffline'] == true
                                ? 'Available on this device'
                                : 'Saved on server · Tap to view',
                            style: T.smallFor(c),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Ic.eye, size: 18, color: c.muted),
                  ],
                ),
              ),
            ],
            if (widget.requiredForDelivery) ...[
              const SizedBox(height: 20),
              BigButton(
                'Continue to Confirm delivery',
                icon: Ic.arrowRight,
                onTap:
                    _busy ||
                        _loading ||
                        _error != null ||
                        _saved.isEmpty ||
                        _draft != null ||
                        !s.canSaveActions
                    ? null
                    : () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
