import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

enum _Step { start, preview, progress, result }

class DetectionScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  const DetectionScreen({super.key, required this.onNavigateTab});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  _Step _step = _Step.start;
  bool _consent = false;
  String _source = 'Upload image';

  void _startPreview(String source) {
    if (AppData.instance.activeChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a child profile first, from Home.')),
      );
      return;
    }
    setState(() {
      _source = source;
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
    setState(() => _step = _Step.progress);
    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    AppData.instance.addRecord(
      MedicalRecord(
        fileName: 'Screening evaluation result',
        type: RecordType.imaging,
        date: _todayLabel(),
      ),
    );

    setState(() => _step = _Step.result);
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  void _reset() {
    setState(() {
      _step = _Step.start;
      _consent = false;
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
        const SizedBox(height: 20),
        Text('Submit an image', style: AppText.heading(18)),
        const SizedBox(height: 6),
        const Text(
          "Choose a clear photo of your child's drawing or handwriting. "
          'This tool provides screening support only and does not make a '
          'diagnosis.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        ActionCard(
          icon: Icons.upload_outlined,
          title: 'Upload image',
          subtitle: 'Choose a file from your device',
          fullWidth: true,
          onTap: () => _startPreview('Upload image'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          icon: Icons.camera_alt_outlined,
          title: 'Capture image',
          subtitle: 'Use your camera',
          fullWidth: true,
          onTap: () => _startPreview('Capture image'),
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
              Container(
                height: 170,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.image_outlined, size: 40, color: AppColors.textFaint),
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _consent = !_consent),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _consent ? AppColors.primary : AppColors.inputBorder,
                width: _consent ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
              color: _consent ? AppColors.successBg : AppColors.surface,
            ),
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
        const SizedBox(height: 16),
        PrimaryButton(label: 'Submit for review', onPressed: _submitForReview),
        const SizedBox(height: 10),
        Center(
          child: TextButton(onPressed: _reset, child: const Text('Choose a different source')),
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
              Text('Processing submission ($_source)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 4),
              const Text('This may take a moment.',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
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
              const Pill(text: 'Preliminary evaluation', bg: AppColors.lavenderBg, fg: AppColors.lavender),
              const SizedBox(height: 12),
              Text('Some signs may be worth looking into further', style: AppText.heading(19)),
              const SizedBox(height: 8),
              const Text(
                'Based on what was submitted, we evaluate that this may be '
                'possible. This is not a diagnosis. We recommend consulting '
                'with a qualified medical professional for a full '
                'assessment.',
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
                    const SnackBar(content: Text('Evaluation details opened.')),
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
