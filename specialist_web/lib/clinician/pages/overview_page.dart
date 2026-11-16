import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../review_dialog.dart';
import '../shell.dart';
import '../widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final now = DateTime.now();
    final pending = data.pendingReview;
    final today = data.appointmentsOn(now);
    final greeting = now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');

    return PageBody(children: [
      PageHeader(
        title: '$greeting, ${data.clinicianName}',
        subtitle: '${fmtWeekday(now)} ${fmtDate(now)}',
        actions: [
          Btn.secondary(
            data.syncing ? 'Refreshing...' : 'Refresh data',
            onPressed: data.syncing ? null : () => data.sync(),
          ),
        ],
      ),
      Panel(
        title: 'Today\'s appointments',
        caption: today.isEmpty ? null : '${today.length} booked',
        trailing: TextLink('Full schedule', onTap: () => Nav.instance.go(Section.schedule)),
        child: today.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No appointments today.', style: TextStyle(color: AppColors.textGrey)),
              )
            : Column(children: [
                for (var i = 0; i < today.length; i++) ...[
                  _AgendaRow(today[i]),
                  if (i < today.length - 1) const Divider(height: 1, color: AppColors.border),
                ],
              ]),
      ),
      const SizedBox(height: 20),
      Panel(
        title: 'Needs attention',
        caption: pending.isEmpty ? null : 'Screenings not yet reviewed, most urgent first',
        trailing: TextLink('All screenings', onTap: () => Nav.instance.go(Section.queue)),
        child: pending.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('All screenings have been reviewed.', style: TextStyle(color: AppColors.textGrey)),
              )
            : Column(children: [
                for (final s in pending.take(5)) _AttentionRow(s),
              ]),
      ),
    ]);
  }
}

class _AttentionRow extends StatelessWidget {
  final Screening s;
  const _AttentionRow(this.s);

  @override
  Widget build(BuildContext context) {
    final p = ClinicScope.of(context).patient(s.patientId);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showReviewDialog(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Avatar(p?.initials ?? '?'),
            const SizedBox(width: 12),
            Expanded(
              child: CellText(p?.fullName ?? 'Unknown',
                  strong: true, sub: '${s.modality.label} screening  ·  ${fmtAgo(s.date)}'),
            ),
            const SizedBox(width: 10),
            ResultTag(s.predictedClass),
          ],
        ),
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final ClinicAppointment a;
  const _AgendaRow(this.a);

  @override
  Widget build(BuildContext context) {
    final p = ClinicScope.of(context).patient(a.patientId);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: p == null ? null : () => Nav.instance.openPatient(p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(fmtTime(a.scheduledAt),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryDark)),
            ),
            Expanded(child: CellText(p?.fullName ?? 'Unknown', strong: true, sub: '${a.type}  ·  ${a.location}')),
            const SizedBox(width: 10),
            VisitStatusTag(a.status),
          ],
        ),
      ),
    );
  }
}
