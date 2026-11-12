import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/payment.dart';
import '../../widgets/workspace.dart';
import 'proof_sheet.dart';

const _quickFailReasons = [
  'Customer unreachable',
  'Address not found',
  'Refused delivery',
  'Business closed',
  'Damaged goods',
];

Future<bool?> showDeliverySheet(
  BuildContext context,
  Trip trip,
  Stop stop,
) async {
  final submitted = await showProofSheet(
    context,
    stop.id,
    requiredForDelivery: true,
    orderLabel: stop.orderLabel,
    customer: stop.customer,
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
      AppScope.of(context).requireSavedAction();
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
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final recipient = widget.stop.contact.isEmpty
        ? widget.stop.customer
        : widget.stop.contact;

    return PopScope(
      canPop: !_busy,
      child: AppBottomSheet(
        title: widget.failed ? 'Report failed attempt' : 'Confirm delivery',
        subtitle: '${widget.stop.orderLabel} · ${widget.stop.customer}',
        canClose: !_busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.failed) PaymentBanner(widget.stop),
            Text(
              widget.failed
                  ? 'Keep undelivered goods for warehouse return. Staff will reconcile the return.'
                  : 'Confirm that all listed goods were handed to $recipient. Payment receipts are recorded separately by staff.',
              style: T.bodyFor(c),
            ),
            const SizedBox(height: 6),
            Text(
              'Saved actions remain pending until the server confirms them.',
              style: T.smallFor(c),
            ),
            const SizedBox(height: 16),
            Panel(
              color: c.surfaceSubtle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.stop.orderLabel, style: T.bodyBoldFor(c)),
                  const SizedBox(height: 2),
                  Text(widget.stop.address, style: T.smallFor(c)),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: c.line),
                  const SizedBox(height: 10),
                  for (final item in widget.stop.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${item.qty} × ${item.name}',
                        style: T.bodyFor(c),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.failed) ...[
              const SizedBox(height: 16),
              Text('Quick reason', style: T.smallBoldFor(c)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _quickFailReasons)
                    ActionChip(
                      label: Text(preset),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _reason.text = preset;
                              _error = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Describe what happened at the stop...',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              FeedbackStrip(_error!),
            ],
            const SizedBox(height: 16),
            BigButton(
              _busy
                  ? 'Saving delivery...'
                  : widget.failed
                  ? 'Report failed attempt'
                  : 'Confirm delivery',
              icon: widget.failed ? Ic.warning : Ic.check,
              style: widget.failed ? BtnStyle.danger : BtnStyle.primary,
              busy: _busy,
              onTap: _busy || !AppScope.of(context).canSaveActions
                  ? null
                  : _submit,
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
