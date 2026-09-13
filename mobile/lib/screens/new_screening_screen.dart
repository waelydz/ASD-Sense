import 'dart:math';
import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class NewScreeningScreen extends StatefulWidget {
  const NewScreeningScreen({super.key});

  @override
  State<NewScreeningScreen> createState() => _NewScreeningScreenState();
}

class _NewScreeningScreenState extends State<NewScreeningScreen> {
  bool _analyzing = false;

  Future<void> _simulateAnalysis(String source) async {
    setState(() => _analyzing = true);

    // Simulate picking + uploading + running the model.
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    final confidence = 88 + Random().nextInt(11); // 88-98%
    final record = MedicalRecord(
      title: 'Autism Screening',
      subtitle: 'Low Risk - $confidence.${Random().nextInt(9)}% confidence',
      date: _todayLabel(),
      kind: RecordKind.screening,
    );
    AppData.instance.addRecord(record);

    setState(() => _analyzing = false);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 10),
            Text('Screening complete'),
          ],
        ),
        content: Text(
          'Image ${source == 'capture' ? 'captured' : 'uploaded'} and '
          'analyzed successfully.\n\nResult: Low Risk\nConfidence: '
          '$confidence.${Random().nextInt(9)}%\n\nThis has been saved to '
          'Medical Records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _todayLabel() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('New Screening'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Text(
                          'Image Guidelines',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.info_outline,
                            size: 18, color: AppColors.textGrey),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Please submit a clear, well-lit photo of your "
                      "child's drawing/handwriting for the most accurate "
                      "screening results.",
                      style: TextStyle(color: AppColors.textGrey, height: 1.4),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'PNG or JPG file (10MB maximum)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ActionCard(
                gradient: true,
                icon: Icons.camera_alt,
                title: 'Capture Image',
                subtitle: 'Take a new photo',
                loading: _analyzing,
                onTap: () => _simulateAnalysis('capture'),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                gradient: false,
                icon: Icons.upload,
                title: 'Upload Image',
                subtitle: 'Choose an existing photo',
                loading: _analyzing,
                onTap: () => _simulateAnalysis('upload'),
              ),
              if (_analyzing) ...[
                const SizedBox(height: 28),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 12),
                      Text(
                        'Analyzing image...',
                        style: TextStyle(color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final bool gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _ActionCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = gradient ? Colors.white : AppColors.textDark;
    final subtitleColor = gradient ? Colors.white70 : AppColors.textGrey;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 34),
        decoration: BoxDecoration(
          gradient: gradient ? AppColors.primaryGradient : null,
          color: gradient ? null : AppColors.surface,
          border: gradient ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: gradient
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppColors.background,
              child: Icon(
                icon,
                color: gradient ? Colors.white : AppColors.textDark,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: subtitleColor)),
          ],
        ),
      ),
    );
  }
}
