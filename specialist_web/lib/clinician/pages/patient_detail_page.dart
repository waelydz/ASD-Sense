import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../review_dialog.dart';
import '../shell.dart';
import '../widgets.dart';

class PatientDetailPage extends StatelessWidget {
  final String patientId;
  const PatientDetailPage({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final p = data.patient(patientId);
    if (p == null) {
      return PageBody(children: [
        PageHeader(
          title: 'Patient not found',
          above: TextLink('Back to patients', onTap: () => Nav.instance.go(Section.patients)),
        ),
      ]);
    }

    final screenings = data.screeningsFor(p.id);
    final reviews = data.reviewsFor(p.id);
    final appts = data.appointmentsFor(p.id);
    final records = data.recordsFor(p.id);
    final now = DateTime.now();
    final upcoming = appts.where((a) => a.scheduledAt.isAfter(now)).toList();
    final past = appts.where((a) => !a.scheduledAt.isAfter(now)).toList().reversed.toList();

    return PageBody(children: [
      PageHeader(
        above: TextLink('Back to patients', onTap: () => Nav.instance.go(Section.patients)),
        title: p.fullName,
        subtitle: '${p.ageLabel}  ·  Born ${fmtDate(p.dateOfBirth)}  ·  ${p.sex}',
        actions: [
          Btn.secondary('Copy summary', onPressed: () => _copySummary(context, p)),
          Btn('Run a screening', onPressed: () => Nav.instance.screenPatient(p.id)),
        ],
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [CaseStatusTag(data.caseStatus(p.id))]),
      const SizedBox(height: 18),
      ResponsiveColumns(
        breakpoint: 1000,
        flex: const [7, 4],
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              title: 'ASD probability over time',
              caption: 'Each point is one screening. The line at 50% is the model decision threshold.',
              child: ProbabilityTrend(screenings),
            ),
            const SizedBox(height: 18),
            Panel(
              title: 'Screening history',
              caption: '${screenings.length} screening${screenings.length == 1 ? '' : 's'}. Select one to review it.',
              child: DataList(
                emptyText: 'No screenings yet.',
                columns: const [
                  Col('Date', flex: 3),
                  Col('Result', flex: 3),
                  Col('Probability', flex: 2),
                  Col('Model', flex: 4, minTableWidth: 560),
                  Col('Your review', flex: 3),
                ],
                rows: [
                  for (final s in screenings)
                    [
                      CellText(fmtShortDate(s.date), sub: fmtTime(s.date)),
                      ResultTag(s.predictedClass),
                      Text(pct(s.autismProbability),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      CellText(s.modelName, sub: s.wasEscalated ? 'Escalated from MobileNet' : s.routing),
                      data.reviews[s.key] == null
                          ? const Text('Not reviewed',
                              style: TextStyle(color: AppColors.lavender, fontWeight: FontWeight.w700, fontSize: 13))
                          : CaseStatusTag(data.reviews[s.key]!.action.short),
                    ],
                ],
                onRowTap: (i) => showReviewDialog(context, screenings[i]),
              ),
            ),
            const SizedBox(height: 18),
            Panel(
              title: 'Clinical notes',
              caption: 'From your screening reviews, newest first',
              child: reviews.isEmpty
                  ? const Text('No notes yet.', style: TextStyle(color: AppColors.textGrey))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final r in reviews) _NoteEntry(r)],
                    ),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              title: 'Family contact',
              child: Column(children: [
                KeyValue('Guardian', p.guardianName),
                KeyValue('Phone', p.guardianPhone),
                KeyValue('Email', p.guardianEmail),
                KeyValue('Referred by', p.referralSource),
              ]),
            ),
            const SizedBox(height: 18),
            Panel(
              title: 'Family\'s records',
              caption: 'Uploaded by the family in the ASD-Sense app',
              child: records.isEmpty
                  ? const Text('No records uploaded.', style: TextStyle(color: AppColors.textGrey))
                  : Column(children: [for (final r in records) _RecordLine(r)]),
            ),
            const SizedBox(height: 18),
            Panel(
              title: 'Appointments',
              caption: 'Added by the family in the ASD-Sense app. Change the status on the Schedule page.',
              child: appts.isEmpty
                  ? const Text('No appointments yet.', style: TextStyle(color: AppColors.textGrey))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (upcoming.isNotEmpty) ...[
                        const _Mini('Upcoming'),
                        for (final a in upcoming) _ApptLine(a),
                      ],
                      if (past.isNotEmpty) ...[
                        if (upcoming.isNotEmpty) const SizedBox(height: 10),
                        const _Mini('Past'),
                        for (final a in past) _ApptLine(a),
                      ],
                    ]),
            ),
          ]),
        ],
      ),
    ]);
  }

  void _copySummary(BuildContext context, Patient p) {
    final data = ClinicData.instance;
    final b = StringBuffer()
      ..writeln('ASD-Sense screening summary')
      ..writeln('Patient: ${p.fullName}, ${p.ageLabel}, born ${fmtDate(p.dateOfBirth)}')
      ..writeln('Guardian: ${p.guardianName} (${p.guardianPhone})')
      ..writeln('Referred by: ${p.referralSource}')
      ..writeln('Current status: ${data.caseStatus(p.id)}')
      ..writeln()
      ..writeln('Screenings:');
    for (final s in data.screeningsFor(p.id)) {
      final r = data.reviews[s.key];
      b.writeln('- ${fmtDate(s.date)}: ${s.modality.label}, ${s.resultLabel}, '
          'probability ${pct(s.autismProbability, 1)}, confidence ${pct(s.confidence, 1)}, ${s.modelName}'
          '${r != null ? '. Clinician: ${r.finding.label.toLowerCase()}; ${r.action.label.toLowerCase()}.' : '. Not yet reviewed.'}');
      if (r != null && r.note.isNotEmpty) b.writeln('  Note: ${r.note}');
    }
    b
      ..writeln()
      ..writeln('AI screening support only; not a diagnosis.')
      ..writeln('Prepared by ${data.signature}${data.specialty.isNotEmpty ? ' (${data.specialty})' : ''} '
          'on ${fmtDate(DateTime.now())}.')
      ..writeln([
        if (data.clinicName.isNotEmpty) data.clinicName,
        if (data.licenceNumber.isNotEmpty) 'Licence ${data.licenceNumber}',
        if (data.workPhone.isNotEmpty) data.workPhone,
      ].join('  ·  '));
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied. Paste it into a referral letter or the patient file.')),
    );
  }
}

class _Mini extends StatelessWidget {
  final String text;
  const _Mini(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

class _RecordLine extends StatelessWidget {
  final FamilyRecord r;
  const _RecordLine(this.r);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: CellText(r.fileName, sub: '${r.typeLabel}  ·  ${fmtDate(r.addedAt)}')),
          if (r.hasFile)
            TextLink('Open', onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ClinicData.instance.openRecord(r);
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            })
          else
            const Text('No file', style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ApptLine extends StatelessWidget {
  final ClinicAppointment a;
  const _ApptLine(this.a);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: CellText(a.type, sub: '${fmtDayHeading(a.scheduledAt)}, ${fmtTime(a.scheduledAt)}')),
          VisitStatusTag(a.status),
        ],
      ),
    );
  }
}

class _NoteEntry extends StatelessWidget {
  final ClinicalReview r;
  const _NoteEntry(this.r);

  @override
  Widget build(BuildContext context) {
    final s = ClinicScope.of(context).screeningByKey(r.screeningKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(left: 14),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border, width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(fmtDate(r.reviewedAt), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(r.reviewer, style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
            CaseStatusTag(r.action.short),
          ]),
          const SizedBox(height: 4),
          Text(
            '${r.finding.label}'
            '${s != null ? ' (${s.modality.label.toLowerCase()} screening of ${fmtShortDate(s.date)}, ${s.resultLabel.toLowerCase()} at ${pct(s.autismProbability)})' : ''}.',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5),
          ),
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.note, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ],
        ],
      ),
    );
  }
}
