import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/sync_panel.dart';
import '../../widgets/workspace.dart';
import 'history_detail_sheet.dart';

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = HyOpsColors.of(context);

    final outcomeField = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: s.historyStatus ?? 'all',
      key: ValueKey(s.historyStatus),
      decoration: const InputDecoration(labelText: 'Outcome'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All outcomes')),
        DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
        DropdownMenuItem(value: 'failed', child: Text('Failed')),
        DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
      ],
      onChanged: s.loading || s.busy
          ? null
          : (value) => s.setHistoryFilter(
              from: s.historyFrom,
              to: s.historyTo,
              status: value == 'all' ? null : value,
            ),
    );

    final dateButton = OutlinedButton.icon(
      icon: const Icon(Ic.calendar, size: 18),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
      ),
      onPressed: s.loading || s.busy
          ? null
          : () async {
              final start = DateTime.tryParse(s.historyFrom ?? '');
              final end = DateTime.tryParse(s.historyTo ?? '');
              final range = await showDateRangePicker(
                context: context,
                helpText: 'Select date range (Manila PHT)',
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: start != null && end != null
                    ? DateTimeRange(start: start, end: end)
                    : null,
              );
              if (range != null && context.mounted) {
                await s.setHistoryFilter(
                  from: _day(range.start),
                  to: _day(range.end),
                  status: s.historyStatus,
                );
              }
            },
      label: Text(
        s.historyFrom == null
            ? 'Date range'
            : '${s.historyFrom} – ${s.historyTo}',
        overflow: TextOverflow.ellipsis,
      ),
    );

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: WorkspaceList(
        children: [
          const WorkspaceHeading(
            'History',
            subtitle: 'Outcomes · Manila (PHT)',
            trailing: SyncStatusHeader(),
          ),
          const SyncPanel(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackFilters =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              if (stackFilters) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    outcomeField,
                    const SizedBox(height: 10),
                    dateButton,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: outcomeField),
                  const SizedBox(width: 10),
                  Expanded(child: dateButton),
                ],
              );
            },
          ),
          if (s.historyFrom != null || s.historyStatus != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: s.loading || s.busy
                    ? null
                    : () => s.setHistoryFilter(),
                icon: const Icon(Ic.close, size: 16),
                label: const Text('Clear filters'),
              ),
            ),
          ],
          SectionTitle(
            s.historyTotal == 1
                ? '1 delivery record'
                : '${s.historyTotal} delivery records',
          ),
          if (s.history.isEmpty)
            DriverEmptyState(
              icon: Ic.history,
              title: s.loading
                  ? 'Loading history...'
                  : s.isOffline
                  ? 'No saved records for this view.'
                  : 'No recorded outcomes yet.',
              message: s.historyFrom != null || s.historyStatus != null
                  ? 'Change or clear the filters to see more records.'
                  : 'Completed delivery outcomes appear here.',
            ),
          for (final e in s.history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                onTap: () => showHistoryDetailSheet(context, e),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(e.customer, style: T.bodyBoldFor(c)),
                                StatusPill(
                                  e.outcome,
                                  tone: e.success ? Tone.green : Tone.danger,
                                ),
                              ],
                            ),
                          ),
                          if (e.orderNumber.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              e.orderNumber,
                              style: T.smallBoldFor(c).copyWith(color: c.ink),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            e.address,
                            style: T.smallFor(c),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!e.success && e.summary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              e.summary,
                              style: T.smallFor(c).copyWith(color: c.danger),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Delivery ${e.tripId} · ${manilaSchedule(e.when)}',
                                  style: T.smallFor(c),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatPhp(e.total),
                                style: T.smallBoldFor(c).copyWith(
                                  color: c.ink,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Ic.chevron, size: 18, color: c.muted),
                  ],
                ),
              ),
            ),
          if (s.historyTotal > 20 || s.historyPage > 0)
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.center,
              children: [
                TextButton(
                  onPressed: s.historyPage > 0 && !s.loading && !s.busy
                      ? () => s.setHistoryPage(s.historyPage - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${s.historyPage + 1}', style: T.smallFor(c)),
                TextButton(
                  onPressed:
                      (s.historyPage + 1) * 20 < s.historyTotal &&
                          !s.loading &&
                          !s.busy
                      ? () => s.setHistoryPage(s.historyPage + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
