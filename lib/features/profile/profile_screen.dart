import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/payment.dart';
import '../../widgets/sync_panel.dart';
import '../../widgets/tracking_badge.dart';
import '../../widgets/workspace.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final driver = state.driver;
    final phoneDisplay = formatPhoneDisplay(driver.phone);

    return WorkspaceList(
      children: [
        const WorkspaceHeading(
          'Profile',
          trailing: SyncStatusHeader(),
        ),
        const SyncPanel(),
        const SizedBox(height: 16),
        WorkspaceColumns(
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Driver account', style: T.titleFor(c)),
              const SizedBox(height: 10),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: c.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: c.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            formatInitials(driver.name),
                            style: T.subheadingFor(c).copyWith(
                              color: c.actionInk,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(driver.name, style: T.titleFor(c)),
                              const SizedBox(height: 2),
                              Text(
                                'Driver ID ${driver.id}',
                                style: T.smallFor(c),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: c.line),
                    const SizedBox(height: 8),
                    if (phoneDisplay.isNotEmpty) KvRow('Phone', phoneDisplay),
                    const KvRow('Vehicle', 'Assigned per trip'),
                  ],
                ),
              ),
              const SectionTitle('Location and connection'),
              Panel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TrackingBadge(),
                    if (state.tracking.status.name != 'idle')
                      const SizedBox(height: 10),
                    Text(
                      'Live GPS sharing runs automatically while signed in online. Signing out stops dispatch location sharing.',
                      style: T.smallFor(c),
                    ),
                  ],
                ),
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Appearance', style: T.titleFor(c)),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: AppThemeMode.system,
                      icon: Icon(Ic.deviceTheme, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('System'),
                      ),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      icon: Icon(Ic.sun, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Light'),
                      ),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      icon: Icon(Ic.moon, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Dark'),
                      ),
                    ),
                  ],
                  selected: {state.themeMode},
                  onSelectionChanged: (modes) =>
                      state.setThemeMode(modes.single),
                ),
              ),
              const SectionTitle('Preferences'),
              Panel(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: state.notifications,
                  onChanged: state.toggleNotifications,
                  secondary: Icon(Ic.bell, size: 20, color: c.muted),
                  title: Text('Assignment alerts', style: T.bodyBoldFor(c)),
                  subtitle: Text(
                    'Show an in-app banner when dispatch assigns or updates a trip.',
                    style: T.smallFor(c),
                  ),
                ),
              ),
              const SectionTitle('Session'),
              BigButton(
                'Sign out',
                icon: Ic.logout,
                style: BtnStyle.dangerOutline,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Sign out of HYOps Driver?'),
                      content: Text(
                        state.pendingSyncCount > 0
                            ? '${state.pendingSyncCount} actions await confirmation. Cancel and sync first, or discard device copies and sign out. Accepted server actions remain recorded. Location sharing will stop.'
                            : 'Location sharing will stop until you sign in again.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.danger,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(
                            state.pendingSyncCount > 0
                                ? 'Discard and sign out'
                                : 'Sign out',
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await state.logout(
                      discardPending: state.pendingSyncCount > 0,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
