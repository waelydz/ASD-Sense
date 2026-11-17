import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../clinic_data.dart';
import '../nav.dart';
import '../shell.dart';
import '../widgets.dart';

/// Session controls, account activity and short guidance on patient data.
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  static const _timeouts = [5, 15, 30, 60, 0];

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final shown = data.activity.take(8).toList();

    return PageBody(children: [
      const PageHeader(title: 'Security'),
      ResponsiveColumns(breakpoint: 980, children: [
        Panel(
          title: 'This session',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeyValue('Signed in as', data.clinicianEmail),
            KeyValue('Since', data.signedInAt == null ? '-' : fmtDateTime(data.signedInAt!)),
            KeyValue('Password',
                data.passwordChangedAt == null ? 'Not changed' : 'Changed ${fmtAgo(data.passwordChangedAt!)}'),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              Btn.secondary('Change password', onPressed: () => Nav.instance.go(Section.settings)),
              Btn('Sign out', onPressed: () => signOutTo(context), kind: BtnKind.danger),
            ]),
          ]),
        ),
        Panel(
          title: 'Automatic sign-out',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final m in _timeouts)
              OptionRow(
                label: m == 0 ? 'Never' : 'After $m minutes',
                detail: m == 15 ? 'Recommended' : null,
                selected: data.autoSignOutMinutes == m,
                onTap: () => data.setAutoSignOut(m),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 20),
      Panel(
        title: 'Recent activity',
        child: shown.isEmpty
            ? const Text('No activity yet.', style: TextStyle(color: AppColors.textGrey))
            : Column(children: [
                for (var i = 0; i < shown.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 130,
                        child: Text('${fmtShortDate(shown[i].at)}, ${fmtTime(shown[i].at)}',
                            style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                      ),
                      Expanded(child: Text(shown[i].text, style: const TextStyle(fontSize: 13.5))),
                    ]),
                  ),
                  if (i < shown.length - 1) const Divider(height: 1, color: AppColors.border),
                ],
              ]),
      ),
      const SizedBox(height: 20),
      ResponsiveColumns(breakpoint: 980, children: [
        Panel(
          title: 'Your access',
          child: ResponsiveColumns(breakpoint: 420, gap: 20, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You can', style: AppText.heading(14, color: AppColors.success)),
              const SizedBox(height: 8),
              const Bullets([
                'View patients\' records, uploaded files and screening images',
                'Review screenings and add notes',
                'Run screenings',
                'Update appointment status',
              ], dot: AppColors.success),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You cannot', style: AppText.heading(14, color: AppColors.danger)),
              const SizedBox(height: 8),
              const Bullets([
                'Book or move appointments',
                'Change model results',
                'Delete screening records',
                'Manage other accounts',
              ], dot: AppColors.danger),
            ]),
          ]),
        ),
        const Panel(
          title: 'Good practice',
          child: Bullets([
            'Only open records of children in your care.',
            'Never share your password or account.',
            'Don\'t download or forward screening images.',
            'Sign out when you leave the computer.',
            'Report anything suspicious to your clinic the same day.',
          ]),
        ),
      ]),
    ]);
  }
}
