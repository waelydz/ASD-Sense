import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../review_dialog.dart';
import '../shell.dart';
import '../widgets.dart';

/// "Screenings" in the sidebar. Unreviewed results are grouped by urgency:
/// flagged first, then inconclusive, then not flagged.
class ReviewQueuePage extends StatefulWidget {
  const ReviewQueuePage({super.key});

  @override
  State<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends State<ReviewQueuePage> {
  bool _showReviewed = false;
  ScreeningModality? _modality;

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    bool keep(Screening s) => _modality == null || s.modality == _modality;

    return PageBody(children: [
      PageHeader(
        title: 'Screenings',
        subtitle: _showReviewed ? 'Screenings you have already reviewed.' : 'Most urgent first.',
      ),
      Wrap(spacing: 14, runSpacing: 12, children: [
        SizedBox(
          width: 220,
          child: Select<bool>(
            value: _showReviewed,
            items: const [false, true],
            itemLabel: (r) => r ? 'Already reviewed' : 'Awaiting review',
            onChanged: (r) => setState(() => _showReviewed = r),
          ),
        ),
        SizedBox(
          width: 200,
          child: Select<ScreeningModality?>(
            value: _modality,
            items: const [null, ScreeningModality.gesture, ScreeningModality.facial],
            itemLabel: (m) => m?.label ?? 'All modalities',
            onChanged: (m) => setState(() => _modality = m),
          ),
        ),
      ]),
      const SizedBox(height: 28),
      if (_showReviewed) ..._reviewed(data, keep) else ..._pending(data, keep),
    ]);
  }

  List<Widget> _pending(ClinicData data, bool Function(Screening) keep) {
    final pending = data.pendingReview.where(keep).toList();
    if (pending.isEmpty) {
      return [const Text('Nothing waiting for review.', style: TextStyle(color: AppColors.textGrey))];
    }
    final flagged = pending.where((s) => s.isFlagged).toList();
    final unsure = pending.where((s) => s.isInconclusive).toList();
    final clear = pending.where((s) => !s.isFlagged && !s.isInconclusive).toList();

    return [
      if (flagged.isNotEmpty)
        _Group(
          title: 'Flagged',
          note: 'Review these first',
          color: AppColors.danger,
          urgency: _Urgency.high,
          items: flagged,
        ),
      if (unsure.isNotEmpty)
        _Group(
          title: 'Inconclusive',
          note: 'Model could not decide',
          color: AppColors.sand,
          urgency: _Urgency.medium,
          items: unsure,
        ),
      if (clear.isNotEmpty)
        _Group(
          title: 'Not flagged',
          note: 'Lower priority',
          color: AppColors.textGrey,
          urgency: _Urgency.low,
          items: clear,
        ),
    ];
  }

  List<Widget> _reviewed(ClinicData data, bool Function(Screening) keep) {
    final list = data.patients
        .expand((p) => data.screeningsFor(p.id))
        .where((s) => data.reviews.containsKey(s.key) && keep(s))
        .toList()
      ..sort((a, b) => data.reviews[b.key]!.reviewedAt.compareTo(data.reviews[a.key]!.reviewedAt));
    if (list.isEmpty) {
      return [const Text('Nothing reviewed yet.', style: TextStyle(color: AppColors.textGrey))];
    }
    return [
      for (var i = 0; i < list.length; i++) ...[
        _Row(s: list[i], urgency: _Urgency.low, trailing: CaseStatusTag(data.reviews[list[i].key]!.action.short)),
        if (i < list.length - 1) const Divider(height: 1, color: AppColors.border),
      ],
    ];
  }
}

enum _Urgency { high, medium, low }

class _Group extends StatelessWidget {
  final String title;
  final String note;
  final Color color;
  final _Urgency urgency;
  final List<Screening> items;

  const _Group({
    required this.title,
    required this.note,
    required this.color,
    required this.urgency,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final high = urgency == _Urgency.high;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: AppText.heading(high ? 21 : 17, color: color, weight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('${items.length}', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(note,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: high ? 3 : 1, color: high ? color : AppColors.border),
          for (var i = 0; i < items.length; i++) ...[
            _Row(s: items[i], urgency: urgency, accent: color),
            if (i < items.length - 1) const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Screening s;
  final _Urgency urgency;
  final Color? accent;
  final Widget? trailing;

  const _Row({required this.s, required this.urgency, this.accent, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = ClinicScope.of(context).patient(s.patientId);
    final high = urgency == _Urgency.high;
    final low = urgency == _Urgency.low;
    final nameColor = low ? AppColors.textGrey : AppColors.textDark;

    return InkWell(
      onTap: () => showReviewDialog(context, s),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: high ? 16 : 12, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p?.fullName ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: high ? 15.5 : 14.5,
                          fontWeight: low ? FontWeight.w600 : FontWeight.w800,
                          color: nameColor)),
                  const SizedBox(height: 2),
                  Text('${s.modality.label} screening  ·  ${fmtAgo(s.date)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (trailing != null)
              trailing!
            else ...[
              Text(pct(s.autismProbability),
                  style: TextStyle(
                      fontSize: high ? 18 : 15,
                      fontWeight: FontWeight.w800,
                      color: low ? AppColors.textGrey : (accent ?? AppColors.textDark))),
              const SizedBox(width: 18),
              Text('Review',
                  style: TextStyle(
                      color: high ? AppColors.danger : AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ],
          ],
        ),
      ),
    );
  }
}
