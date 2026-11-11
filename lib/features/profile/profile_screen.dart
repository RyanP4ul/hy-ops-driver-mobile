import 'package:flutter/material.dart';

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
    final driver = state.driver;
    return WorkspaceList(
      children: [
        const WorkspaceHeading('Profile'),
        const SizedBox(height: 24),
        WorkspaceColumns(
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Driver account', style: T.title),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name, style: T.title),
                    Text('Driver ID ${driver.id}', style: T.small),
                    const SizedBox(height: 12),
                    const Divider(),
                    KvRow('Phone', driver.phone),
                    const KvRow('Vehicle', 'Assigned per trip'),
                  ],
                ),
              ),
              const SectionTitle('Location and connection'),
              const TrackingBadge(),
              const SyncPanel(),
              Text(
                'Signing out stops location sharing with dispatch.',
                style: T.small,
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Appearance', style: T.title),
              const SizedBox(height: 12),
              for (final (mode, label, icon) in const [
                (
                  AppThemeMode.system,
                  'System',
                  Icons.settings_brightness_outlined,
                ),
                (AppThemeMode.light, 'Light', Icons.light_mode_outlined),
                (AppThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
              ]) ...[
                ListTile(
                  tileColor: P.surface,
                  selected: state.themeMode == mode,
                  selectedTileColor: P.primarySoft,
                  selectedColor: P.ink,
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: state.themeMode == mode
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => state.setThemeMode(mode),
                ),
                const Divider(),
              ],
              const SectionTitle('Session'),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Ic.logout),
                  label: const Text('Sign out'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign out of HYOps Driver?'),
                        content: const Text(
                          'Location sharing will stop until you sign in again.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted)
                      await state.logout();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
