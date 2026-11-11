import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/format.dart';
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
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: WorkspaceList(
        children: [
          const WorkspaceHeading('History', subtitle: 'Delivery outcomes'),
          const SyncPanel(),
          WorkspaceColumns(
            stackSpacing: 10,
            first: DropdownButtonFormField<String>(
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
            ),
            second: OutlinedButton.icon(
              icon: const Icon(Icons.date_range_outlined),
              onPressed: s.loading || s.busy
                  ? null
                  : () async {
                      final start = DateTime.tryParse(s.historyFrom ?? '');
                      final end = DateTime.tryParse(s.historyTo ?? '');
                      final range = await showDateRangePicker(
                        context: context,
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
                    ? 'Filter by Manila dates'
                    : '${s.historyFrom} to ${s.historyTo} (Manila)',
              ),
            ),
          ),
          if (s.historyFrom != null || s.historyStatus != null)
            TextButton(
              onPressed: s.loading || s.busy
                  ? null
                  : () => s.setHistoryFilter(),
              child: const Text('Clear filters'),
            ),
          SectionTitle(
            s.historyTotal == 1
                ? '1 delivery record'
                : '${s.historyTotal} delivery records',
          ),
          if (s.history.isEmpty)
            DriverEmptyState(
              icon: Icons.history,
              title: s.loading
                  ? 'Loading history...'
                  : s.isOffline
                  ? 'No saved records for this view.'
                  : 'No recorded outcomes yet.',
              message: s.historyFrom != null || s.historyStatus != null
                  ? 'Change or clear the filters to see more records.'
                  : 'Completed delivery outcomes appear here.',
            ),
          for (final e in s.history) ...[
            RecordRow(
              onTap: () => showHistoryDetailSheet(context, e),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(e.customer, style: T.bodyBold),
                      StatusPill(
                        e.outcome,
                        tone: e.success ? Tone.green : Tone.danger,
                      ),
                    ],
                  ),
                  if (e.orderNumber.isNotEmpty)
                    Text(e.orderNumber, style: T.bodyBold),
                  Text(e.address, style: T.small),
                  Text('Delivery ${e.tripId}', style: T.bodyBold),
                  Text(e.summary, style: T.body),
                  Text('${manilaSchedule(e.when)} (Manila)', style: T.small),
                ],
              ),
            ),
            const Divider(),
          ],
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
                Text('Page ${s.historyPage + 1}'),
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
