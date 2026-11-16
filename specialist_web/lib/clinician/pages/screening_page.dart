import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../review_dialog.dart';
import '../shell.dart';
import '../widgets.dart';

/// Run a screening in clinic. Unlike the guardian flow this shows the full
/// model output. The result is saved under the chosen patient's child_id.
class ScreeningPage extends StatefulWidget {
  const ScreeningPage({super.key});

  @override
  State<ScreeningPage> createState() => _ScreeningPageState();
}

class _ScreeningPageState extends State<ScreeningPage> {
  final data = ClinicData.instance;
  String? _patientId;
  ScreeningModality _modality = ScreeningModality.gesture;
  String? _fileName;
  Uint8List? _bytes;
  bool _consent = false;
  bool _running = false;
  String? _error;
  Screening? _result;

  @override
  void initState() {
    super.initState();
    final pre = Nav.instance.screeningPatientId;
    Nav.instance.screeningPatientId = null;
    _patientId = data.patient(pre ?? '') != null ? pre : null;
  }

  /// The chosen patient, or the first one. Null when there are no patients, or
  /// the chosen one was deleted by the family while this page was open.
  Patient? get _patient => data.patient(_patientId ?? '') ?? (data.patients.isEmpty ? null : data.patients.first);

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    if (!mounted || file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fileName = file.name;
      _bytes = bytes;
      _result = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final p = _patient;
    if (p == null || _bytes == null || !_consent) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await ApiClient.instance.predict(
        modality: _modality,
        childId: p.childId,
        bytes: _bytes!,
        fileName: _fileName ?? 'upload.jpg',
      );
      if (!mounted) return;
      setState(() => _result = data.recordLiveResult(p, r, _fileName ?? 'upload.jpg'));
    } on ApiException catch (e) {
      if (!mounted) return;
      // The backend's reason, e.g. models not loaded or an unreadable image.
      setState(() => _error = 'The screening could not be run. ${e.message}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _reset() => setState(() {
        _fileName = null;
        _bytes = null;
        _consent = false;
        _result = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    ClinicScope.of(context); // rebuild when shared data changes
    final p = _patient;
    final canRun = p != null && _bytes != null && _consent && !_running;

    const header = PageHeader(
      title: 'Run a screening',
      subtitle: 'Upload an image taken in clinic. The result is saved to the patient\'s record.',
    );
    if (p == null) {
      return const PageBody(children: [
        header,
        Notice('There are no patients yet. Add one on the Patients page, or wait for a family to '
            'create a child profile in the ASD-Sense app.'),
      ]);
    }

    return PageBody(children: [
      header,
      ResponsiveColumns(
        breakpoint: 980,
        flex: const [5, 6],
        children: [
          Panel(
            title: '1. Patient and modality',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Select<String>(
                label: 'Patient',
                value: p.id,
                items: [for (final x in data.patients) x.id],
                itemLabel: (id) => data.patient(id)?.fullName ?? '-',
                onChanged: (id) => setState(() {
                  _patientId = id;
                  _result = null;
                }),
              ),
              const SizedBox(height: 18),
              const FieldLabel('Modality'),
              OptionRow(
                label: 'Hand gesture',
                detail: 'POST /api/clinic/predict/gesture',
                selected: _modality == ScreeningModality.gesture,
                onTap: () => setState(() => _modality = ScreeningModality.gesture),
              ),
              OptionRow(
                label: 'Facial',
                detail: 'POST /api/clinic/predict/facial. Use a clear, front-facing image.',
                selected: _modality == ScreeningModality.facial,
                onTap: () => setState(() => _modality = ScreeningModality.facial),
              ),
              const SizedBox(height: 18),
              Text('2. Image', style: AppText.heading(16.5)),
              const SizedBox(height: 12),
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: _bytes == null
                    ? const Text('No image chosen', style: TextStyle(color: AppColors.textFaint))
                    : Image.memory(_bytes!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Btn.secondary(_bytes == null ? 'Choose image' : 'Choose a different image', onPressed: _pick),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_fileName ?? 'JPG or PNG',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _consent = !_consent),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(
                    value: _consent,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Guardian consent for AI screening is recorded in the patient file.',
                        style: TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Btn('Run screening', onPressed: canRun ? _run : null, loading: _running, expand: true),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Notice(_error!, warning: true),
              ],
            ]),
          ),
          _resultPanel(context),
        ],
      ),
    ]);
  }

  Widget _resultPanel(BuildContext context) {
    final s = _result;
    if (s == null) {
      return Panel(
        title: '3. Result',
        child: Container(
          height: 240,
          alignment: Alignment.center,
          child: Text(
            _running ? 'Running ${_modality.label.toLowerCase()} model...' : 'The full model output will appear here.',
            style: const TextStyle(color: AppColors.textGrey),
          ),
        ),
      );
    }
    return Panel(
      title: '3. Result',
      caption: 'Saved as screening #${s.id}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ResultTag(s.predictedClass),
          const SizedBox(width: 12),
          Text(pct(s.autismProbability, 1), style: AppText.heading(30, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          const Text('ASD probability', style: TextStyle(color: AppColors.textGrey)),
        ]),
        const SizedBox(height: 14),
        KeyValue('Raw class', s.predictedClass),
        KeyValue('Confidence', pct(s.confidence, 1)),
        KeyValue('Model', s.modelName),
        KeyValue('Routing', s.routing ?? '-'),
        KeyValue('Image file', s.imageReference ?? '-'),
        const SizedBox(height: 12),
        if (s.wasEscalated) const Notice('MobileNetV2 was under 85% confident, so ViT-B/16 re-scored this image.'),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          Btn('Review now', onPressed: () => showReviewDialog(context, s)),
          Btn.secondary('Open patient record', onPressed: () => Nav.instance.openPatient(s.patientId)),
          Btn.quiet('Start another', onPressed: _reset),
        ]),
      ]),
    );
  }
}
