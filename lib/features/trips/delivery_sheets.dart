import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data/models.dart';
import '../../core/palette.dart';
import '../../widgets/common.dart';
import '../../widgets/workspace.dart';
import '../../state/app_state.dart';
import 'proof_sheet.dart';

Future<bool?> showDeliverySheet(
  BuildContext context,
  Trip trip,
  Stop stop,
) async {
  final submitted = await showProofSheet(
    context,
    stop.id,
    requiredForDelivery: true,
  );
  if (submitted != true || !context.mounted) return null;
  return _show(context, trip, stop, false);
}

Future<bool?> showIssueSheet(BuildContext context, Trip trip, Stop stop) =>
    _show(context, trip, stop, true);

Future<bool?> _show(BuildContext context, Trip trip, Stop stop, bool failed) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _OutcomeSheet(trip: trip, stop: stop, failed: failed),
    );

class _OutcomeSheet extends StatefulWidget {
  final Trip trip;
  final Stop stop;
  final bool failed;
  const _OutcomeSheet({
    required this.trip,
    required this.stop,
    required this.failed,
  });
  @override
  State<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends State<_OutcomeSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.failed && _reason.text.trim().isEmpty) {
      setState(
        () => _error = 'Describe why the delivery could not be completed.',
      );
      return;
    }
    try {
      AppScope.of(context).requireOnlineAction();
    } catch (e) {
      setState(() => _error = apiError(e));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).recordOutcome(
        widget.trip,
        widget.stop,
        reason: widget.failed ? _reason.text.trim() : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.failed ? 'Report failed attempt' : 'Confirm delivery',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                widget.failed
                    ? 'Keep undelivered goods for warehouse return. Staff will reconcile the return.'
                    : 'Confirm that all listed goods were handed to ${widget.stop.contact}. Payment receipts are recorded separately by staff.',
              ),
              const SizedBox(height: 16),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.stop.orderLabel, style: T.bodyBold),
                    Text(widget.stop.address, style: T.small),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    for (final item in widget.stop.items)
                      Text('${item.qty} × ${item.name}', style: T.body),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (widget.failed)
                TextField(
                  controller: _reason,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              if (_error != null) FeedbackStrip(_error!),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: widget.failed
                      ? FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onError,
                        )
                      : null,
                  onPressed: _busy || AppScope.of(context).isOffline
                      ? null
                      : _submit,
                  child: Text(
                    _busy
                        ? 'Saving delivery...'
                        : widget.failed
                        ? 'Report failed attempt'
                        : 'Confirm delivery',
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Go back'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
