import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

enum _Step { start, preview, progress, result }

/// The two screening models the user can choose between.
enum AnalysisPath {
  hand(
    'Hand gesture analysis',
    'For hand gestures and drawing-based visual input.',
    "Choose a clear photo of your child's hand drawing or gesture.",
  ),
  face(
    'Facial recognition analysis',
    'For facial features and facial-expression visual input.',
    "Choose a clear, front-facing photo of your child's face.",
  );

  final String title;
  final String subtitle;
  final String uploadHint;
  const AnalysisPath(this.title, this.subtitle, this.uploadHint);
}

class DetectionScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  const DetectionScreen({super.key, required this.onNavigateTab});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // Replace 192.168.1.XX with your PC's IPv4 address from ipconfig
  static const String _backendBaseUrl = 'http://192.168.1.226:8000';

  _Step _step = _Step.start;
  bool _consent = false;
  AnalysisPath _path = AnalysisPath.hand;
  String? _fileName;
  Uint8List? _fileBytes;

  // API Response fields
  String? _predictedClass;
  double? _autismProbability;
  double? _confidence;
  String? _modelUsed;

  Future<void> _pickImage() async {
    if (AppData.instance.activeChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a child profile first, from Home.')),
      );
      return;
    }

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    if (!mounted || file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() {
      _fileName = file.name;
      _fileBytes = bytes;
      _step = _Step.preview;
    });
  }

  Future<void> _submitForReview() async {
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm consent before submitting.')),
      );
      return;
    }
    if (_fileBytes == null) return;

    setState(() => _step = _Step.progress);

    try {
      final endpoint = _path == AnalysisPath.hand
          ? '$_backendBaseUrl/predict/gesture'
          : '$_backendBaseUrl/predict/gesture'; // Will point to /predict/facial once facial models are added

      final request = http.MultipartRequest('POST', Uri.parse(endpoint));
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _fileBytes!,
          filename: _fileName ?? 'upload.jpg',
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final predClass = data['predicted_class'] as String?;
        final prob = (data['autism_probability'] as num?)?.toDouble();
        final conf = (data['confidence'] as num?)?.toDouble();
        final modelName = data['model_name'] as String?;

        AppData.instance.addRecord(
          MedicalRecord(
            fileName: '${_path.title} (${predClass ?? "result"})',
            type: RecordType.imaging,
            date: _todayLabel(),
          ),
        );

        setState(() {
          _predictedClass = predClass;
          _autismProbability = prob;
          _confidence = conf;
          _modelUsed = modelName;
          _step = _Step.result;
        });
      } else {
        setState(() => _step = _Step.preview);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error (${response.statusCode}): ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.preview);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect to server at $_backendBaseUrl')),
      );
    }
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  void _reset() {
    setState(() {
      _step = _Step.start;
      _consent = false;
      _fileName = null;
      _fileBytes = null;
      _predictedClass = null;
      _autismProbability = null;
      _confidence = null;
      _modelUsed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MainHeader(
                title: 'Detection',
                onProfileTap: () => widget.onNavigateTab(4),
              ),
              const SizedBox(height: 18),
              if (_step == _Step.start) _buildStart(),
              if (_step == _Step.preview) _buildPreview(),
              if (_step == _Step.progress) _buildProgress(),
              if (_step == _Step.result) _buildResult(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AlertBanner(
          title: 'Your privacy matters.',
          body:
              'Images you submit are used only to generate this evaluation '
              'and are not shared without your consent.',
        ),
        const SizedBox(height: 22),
        Text('Choose an analysis path', style: AppText.heading(18)),
        const SizedBox(height: 6),
        const Text(
          'Select the type of input before adding an image. Each path uses '
          'its own model. This tool provides screening support only and does '
          'not make a diagnosis.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (final path in AnalysisPath.values) ...[
          ChoiceCard(
            label: path.title,
            subtitle: path.subtitle,
            selected: _path == path,
            onTap: () => setState(() => _path = path),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_path.title, style: AppText.heading(16)),
              const SizedBox(height: 4),
              Text(
                _path.uploadHint,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              SecondaryButton(label: 'Choose image', onPressed: _pickImage),
              const SizedBox(height: 8),
              const Text(
                'Supported formats: JPG, PNG.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review submission', style: AppText.heading(18)),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            children: [
              Pill(text: _path.title, bg: AppColors.sageBg, fg: AppColors.sage),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 190,
                  width: double.infinity,
                  color: AppColors.paper,
                  alignment: Alignment.center,
                  child: _fileBytes != null
                      ? Image.memory(_fileBytes!, fit: BoxFit.contain)
                      : Text(
                          _fileName ?? 'No preview available',
                          style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Image preview. Submitted images are not stored after review.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: _consent ? AppColors.successBg : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _consent ? AppColors.primary : AppColors.inputBorder,
              width: _consent ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => setState(() => _consent = !_consent),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: _consent,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'I confirm I have consent to submit this image for '
                      'screening support.',
                      style: TextStyle(color: AppColors.textDark, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Submit for review', onPressed: _submitForReview),
        const SizedBox(height: 10),
        Center(
          child: TextButton(onPressed: _reset, child: const Text('Choose a different image')),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preparing your evaluation', style: AppText.heading(18)),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Running ${_path.title.toLowerCase()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'This may take a moment.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: const LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.border,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final isAutistic = _predictedClass == 'autistic';
    final isNonAutistic = _predictedClass == 'non_autistic';
    final confPercent = _confidence != null ? '${(_confidence! * 100).toStringAsFixed(1)}%' : 'N/A';

    final headline = isAutistic
        ? 'Some signs may be worth looking into further'
        : isNonAutistic
            ? 'No strong indicators detected in this screening'
            : 'Screening result was inconclusive';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evaluation result', style: AppText.heading(18)),
        const SizedBox(height: 14),
        SectionCard(
          bg: AppColors.successBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pill(
                text: 'Confidence: $confPercent (${_modelUsed ?? "AI Model"})',
                bg: AppColors.lavenderBg,
                fg: AppColors.lavender,
              ),
              const SizedBox(height: 12),
              Text(headline, style: AppText.heading(19)),
              const SizedBox(height: 8),
              const Text(
                'Based on what was submitted, this preliminary screening has been '
                'logged to your child\'s records. This is not a medical diagnosis. '
                'We recommend consulting with a qualified clinician for a full assessment.',
                style: TextStyle(color: AppColors.primaryDark, fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ActionCard(
                icon: Icons.find_in_page_outlined,
                title: 'Review details',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Class: ${_predictedClass ?? "N/A"} | ASD Prob: $_autismProbability | Model: $_modelUsed',
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ActionCard(
                icon: Icons.event_note_outlined,
                title: 'Consult clinician',
                onTap: () => widget.onNavigateTab(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Provide feedback',
          onPressed: () {
            final controller = TextEditingController();
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Provide feedback', style: AppText.heading(18)),
                      const SizedBox(height: 14),
                      LabelledTextField(
                        label: 'Feedback',
                        hint: 'Share your feedback',
                        controller: controller,
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Save feedback',
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Feedback saved.')),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(onPressed: _reset, child: const Text('Start a new evaluation')),
        ),
      ],
    );
  }
}