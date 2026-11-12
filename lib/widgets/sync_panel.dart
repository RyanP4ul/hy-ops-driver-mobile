import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/palette.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'workspace.dart';

/// Compact header status chip + refresh action when sync is healthy.
class SyncStatusHeader extends StatelessWidget {
  final bool iconOnly;

  const SyncStatusHeader({super.key, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final syncing = s.loading || s.isStartupValidating || s.isSyncing;
    final label = syncing
        ? 'Updating…'
        : s.lastSynced == null
        ? 'Not synced'
        : s.isOffline
        ? 'Saved ${fmtWhen(s.lastSynced!.toLocal())}'
        : 'Synced ${fmtTime(s.lastSynced!.toLocal())}';
    final dotColor = s.isOffline
        ? c.warn
        : syncing
        ? c.info
        : c.success;

    final refreshButton = IconButton(
      tooltip: s.isOffline ? 'Retry connection' : 'Refresh assignments',
      onPressed: s.loading || s.busy || s.isSyncing ? null : s.synchronize,
      icon: const Icon(Ic.refresh, size: 18),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );

    if (iconOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: label,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          refreshButton,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: T.smallBoldFor(c).copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        refreshButton,
      ],
    );
  }
}

/// Pinned top banner rendered only when connection, sync queue, or errors
/// need driver awareness or action.
class SyncPanel extends StatelessWidget {
  final bool showWhenHealthy;

  const SyncPanel({super.key, this.showWhenHealthy = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final sync = s.repository.sync;
    final hasQueue =
        s.repository.syncSupported &&
        (sync.syncing ||
            sync.hasOldWork ||
            sync.reconciliationCount > 0 ||
            sync.attentionCount > 0 ||
            s.pendingSyncCount > 0 ||
            sync.error != null ||
            sync.commands.any((cmd) => cmd.pending));
    final showBanner = s.isOffline || s.error != null || s.loading || hasQueue;

    if (!showBanner && !showWhenHealthy) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(minHeight: 2),
              ),
            ),
          if (s.isOffline)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FeedbackStrip(
                s.offlineActionRestriction ??
                    'Offline - ${s.pendingSyncCount} ${pluralize(s.pendingSyncCount, 'change')} saved. Sync resumes automatically.',
                warning: true,
              ),
            ),
          if (s.repository.syncSupported && sync.hasOldWork)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: FeedbackStrip(
                'Saved work is approaching 30 days. Connect and review it with staff. Unresolved actions remain saved.',
                warning: true,
              ),
            ),
          if (s.repository.syncSupported && sync.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FeedbackStrip(sync.error!, warning: true),
            ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FeedbackStrip(s.error!),
            ),
          if (hasQueue || showWhenHealthy)
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: sync.attentionCount > 0 ? c.warnSoft : c.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sync.syncing
                              ? 'Synchronizing saved work...'
                              : sync.attentionCount > 0
                              ? '${sync.attentionCount} ${pluralize(sync.attentionCount, 'action')} need attention'
                              : s.pendingSyncCount > 0
                              ? '${s.pendingSyncCount} ${pluralize(s.pendingSyncCount, 'change')} pending sync'
                              : 'Up to date',
                          style: T.bodyBoldFor(c).copyWith(fontSize: 14),
                        ),
                        if (sync.uploadBytesTotal > 0 && sync.syncing)
                          Text(
                            'Uploading proof ${(100 * sync.uploadedBytes / sync.uploadBytesTotal).round()}%',
                            style: T.smallFor(c),
                          )
                        else if (sync.reconciliationCount > 0)
                          Text(
                            '${sync.reconciliationCount} accepted changes awaiting refresh',
                            style: T.smallFor(c),
                          )
                        else if (sync.lastPush != null)
                          Text(
                            'Last upload ${fmtWhen(sync.lastPush!.toLocal())}',
                            style: T.smallFor(c),
                          ),
                      ],
                    ),
                  ),
                  if (s.repository.syncSupported &&
                      sync.commands.any((cmd) => cmd.pending))
                    TextButton(
                      onPressed: () => _openSavedWorkSheet(context, s),
                      child: const Text('Saved work'),
                    ),
                  if (showWhenHealthy)
                    IconButton(
                      tooltip: s.isOffline
                          ? 'Retry connection'
                          : 'Refresh assignments',
                      onPressed: s.loading || s.busy || s.isSyncing
                          ? null
                          : s.synchronize,
                      icon: const Icon(Ic.refresh, size: 18),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openSavedWorkSheet(BuildContext context, AppState s) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final state = AppScope.of(sheetContext);
          final c = HyOpsColors.of(sheetContext);
          final pending = state.repository.sync.commands
              .where((cmd) => cmd.pending)
              .toList();
          return AppBottomSheet(
            title: 'Saved offline work',
            subtitle:
                'Queued actions upload automatically once connection stabilizes.',
            fixedHeightFraction: 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'All saved actions have been synced.',
                      style: T.bodyFor(c),
                    ),
                  ),
                for (final cmd in pending) ...[
                  Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${cmd.kind} · Delivery ${cmd.tripId}',
                                style: T.bodyBoldFor(c),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cmd.errorMessage ??
                                    'Saved on device - pending sync',
                                style: T.smallFor(c),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (cmd.sendPayload == null || cmd.needsAttention)
                          IconButton(
                            tooltip: 'Review and discard',
                            icon: Icon(Ic.trash, size: 18, color: c.danger),
                            onPressed: state.isSyncing
                                ? null
                                : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: sheetContext,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text(
                                          'Review and discard this action?',
                                        ),
                                        content: const Text(
                                          'Attempted actions require an online check before removal. Discard dependent deliveries before removing their proof. A corrected action must be recorded again.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                              false,
                                            ),
                                            child: const Text('Keep saved'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: c.danger,
                                            ),
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                              true,
                                            ),
                                            child: const Text('Discard'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true) return;
                                    try {
                                      await state.repository.discardUnsent(
                                        cmd.key,
                                      );
                                      if (sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
                                      }
                                    } catch (failure) {
                                      if (context.mounted) {
                                        toast(context, '$failure');
                                      }
                                    }
                                  },
                          )
                        else
                          Icon(
                            cmd.needsAttention ? Ic.alert : Ic.clock,
                            size: 18,
                            color: cmd.needsAttention ? c.warn : c.muted,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                Text(
                  'Conflicting work stays saved. Review the current assignment with staff before discarding or recording a corrected action.',
                  style: T.smallFor(c),
                ),
                const SizedBox(height: 16),
                BigButton(
                  state.isSyncing ? 'Syncing...' : 'Retry sync',
                  icon: Ic.refresh,
                  busy: state.isSyncing,
                  onTap: state.isSyncing || state.loading || state.busy
                      ? null
                      : state.synchronize,
                ),
              ],
            ),
          );
        },
      );
}

/// Full-app blocking spinner dialog rendered while synchronization is in progress.
class SyncGate extends StatefulWidget {
  final bool active;
  final bool uploadingOutbox;
  final int uploadedBytes;
  final int uploadBytesTotal;
  final Widget child;

  const SyncGate({
    super.key,
    required this.active,
    required this.uploadingOutbox,
    this.uploadedBytes = 0,
    this.uploadBytesTotal = 0,
    required this.child,
  });

  @override
  State<SyncGate> createState() => _SyncGateState();
}

class _SyncGateState extends State<SyncGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => widget.active;

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final hasUploadProgress =
        widget.uploadingOutbox && widget.uploadBytesTotal > 0;
    final percent = hasUploadProgress
        ? (100 * widget.uploadedBytes / widget.uploadBytesTotal)
              .clamp(0, 100)
              .round()
        : 0;
    final title = widget.uploadingOutbox
        ? 'Synchronizing saved work…'
        : 'Syncing…';
    final subtitle = hasUploadProgress
        ? 'Uploading proof ($percent%). Please wait…'
        : 'Please wait until syncing finishes.';

    return Stack(
      children: [
        ExcludeFocus(
          excluding: widget.active,
          child: ExcludeSemantics(
            excluding: widget.active,
            child: AbsorbPointer(absorbing: widget.active, child: widget.child),
          ),
        ),
        if (widget.active) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0x88000000)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Material(
                      key: const Key('sync-blocking-dialog'),
                      color: c.surface,
                      elevation: 8,
                      shadowColor: Colors.black38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: c.line),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              liveRegion: true,
                              label: title,
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              title,
                              style: T.titleFor(c),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: T.smallFor(c),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
