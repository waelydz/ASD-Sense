import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'api_client.dart';
import 'clinic_data.dart';
import 'models.dart';
import 'nav.dart';
import 'widgets.dart';

/// Lets a clinician confirm or override a model result and record next steps.
Future<void> showReviewDialog(BuildContext context, Screening screening) {
  return showDialog(
    context: context,
    builder: (_) => _ReviewDialog(screening: screening),
  );
}

class _ReviewDialog extends StatefulWidget {
  final Screening screening;
  const _ReviewDialog({required this.screening});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final data = ClinicData.instance;
  late ClinicalFinding _finding;
  late RecommendedAction _action;
  late final TextEditingController _note;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = data.reviews[widget.screening.key];
    _finding = existing?.finding ?? ClinicalFinding.agree;
    _action = existing?.action ?? _suggestedAction(widget.screening);
    _note = TextEditingController(text: existing?.note ?? '');
    _editing = existing == null;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  RecommendedAction _suggestedAction(Screening s) {
    if (s.isFlagged) return RecommendedAction.referDiagnostic;
    if (s.isInconclusive) return RecommendedAction.rescreen;
    return RecommendedAction.monitor;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await data.saveReview(
        screening: widget.screening,
        finding: _finding,
        action: _action,
        note: _note.text.trim(),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('The review was not saved. ${e.message}')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(content: Text('Review saved.')));
  }

  @override
  Widget build(BuildContext context) {
    ClinicScope.of(context); // rebuild when shared data changes
    final s = widget.screening;
    final patient = data.patient(s.patientId);
    final existing = data.reviews[s.key];
    final width = MediaQuery.sizeOf(context).width;

    return Dialog(
      backgroundColor: AppColors.paper,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 880, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(width < 600 ? 18 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Screening review', style: AppText.heading(22)),
                        const SizedBox(height: 4),
                        Text(
                          '${patient?.fullName ?? 'Unknown patient'}'
                          '${patient != null ? '  ·  ${patient.ageLabel}' : ''}',
                          style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Btn.quiet('Close', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 18),
              ResponsiveColumns(
                breakpoint: 720,
                flex: const [5, 6],
                children: [
                  _modelOutput(s),
                  existing != null && !_editing ? _savedReview(existing) : _form(s),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelOutput(Screening s) {
    return Panel(
      title: 'Model output',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValue('Result', '',
              valueWidget: Align(alignment: Alignment.centerLeft, child: ResultTag(s.predictedClass))),
          KeyValue('Raw class', s.predictedClass),
          KeyValue('ASD probability', '', valueWidget: ProbabilityBar(s.autismProbability)),
          KeyValue('Confidence', pct(s.confidence, 1)),
          KeyValue('Model', '${s.modelName}${s.modelVersion != null ? ' v${s.modelVersion}' : ''}'),
          KeyValue('Routing', s.routing ?? '-'),
          KeyValue('Modality', s.modality.label),
          KeyValue('Submitted', fmtDateTime(s.date)),
          KeyValue('Image file', s.imageReference ?? '-'),
          const SizedBox(height: 12),
          _screenedImage(s),
          const SizedBox(height: 12),
          if (s.wasEscalated)
            const Notice(
              'MobileNetV2 confidence was below 85%, so the image was re-scored by the ViT-B/16 model. '
              'The probability shown is from ViT.',
            )
          else if (s.isInconclusive)
            const Notice(
              'Confidence was below 60%, so the model marked this inconclusive.',
              warning: true,
            ),
          const SizedBox(height: 10),
          const Text(
            'The models only screen a single image. They are not a diagnosis and '
            'should be weighed with history and observation.',
            style: TextStyle(color: AppColors.textGrey, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// The image the model scored, so the result can be judged against it.
  Widget _screenedImage(Screening s) {
    Widget placeholder(String text) => Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(text, style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        );
    if (!s.hasImage) return placeholder('No image is stored for this screening.');
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 240,
        width: double.infinity,
        color: AppColors.paper,
        child: Image.network(
          ApiClient.instance.screeningImageUrl(s.id),
          headers: ApiClient.instance.authHeaders,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
          errorBuilder: (_, __, ___) => placeholder('The image could not be loaded.'),
        ),
      ),
    );
  }

  Widget _form(Screening s) {
    return Panel(
      title: 'Your assessment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Finding'),
          for (final f in ClinicalFinding.values)
            OptionRow(
              label: f.label,
              selected: _finding == f,
              onTap: () => setState(() => _finding = f),
            ),
          const SizedBox(height: 8),
          Select<RecommendedAction>(
            label: 'Next step',
            value: _action,
            items: RecommendedAction.values,
            itemLabel: (a) => a.label,
            onChanged: (a) => setState(() => _action = a),
          ),
          const SizedBox(height: 14),
          Field(
            label: 'Clinical note',
            hint: 'Observations, history, image quality, what you told the family...',
            controller: _note,
            maxLines: 4,
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Btn('Save review', onPressed: _save, loading: _saving),
            if (data.reviews.containsKey(s.key))
              Btn.secondary('Cancel', onPressed: () => setState(() => _editing = false)),
          ]),
        ],
      ),
    );
  }

  Widget _savedReview(ClinicalReview r) {
    return Panel(
      title: 'Reviewed',
      caption: '${r.reviewer}, ${fmtDateTime(r.reviewedAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValue('Finding', r.finding.label),
          KeyValue('Next step', r.action.label),
          KeyValue('Note', r.note.isEmpty ? '-' : r.note),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Btn.secondary('Edit review', onPressed: () => setState(() => _editing = true)),
            Btn.secondary('Open patient record', onPressed: () {
              Navigator.of(context).pop();
              Nav.instance.openPatient(widget.screening.patientId);
            }),
          ]),
        ],
      ),
    );
  }
}
