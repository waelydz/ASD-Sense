import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class MedicalRecordsScreen extends StatelessWidget {
  const MedicalRecordsScreen({super.key});

  void _openAddRecordSheet(BuildContext context) {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
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
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Text(
                  'Add Medical Record',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                LabelledTextField(
                  label: 'Title',
                  hint: 'e.g. Dental Checkup',
                  controller: titleController,
                ),
                const SizedBox(height: 14),
                LabelledTextField(
                  label: 'Details',
                  hint: 'e.g. Healthy, no issues found',
                  controller: subtitleController,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Save Record',
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    AppData.instance.addRecord(
                      MedicalRecord(
                        title: titleController.text.trim(),
                        subtitle: subtitleController.text.trim().isEmpty
                            ? 'No additional details'
                            : subtitleController.text.trim(),
                        date: _todayLabel(),
                      ),
                    );
                    Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _todayLabel() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  IconData _iconFor(RecordKind kind) {
    switch (kind) {
      case RecordKind.screening:
        return Icons.monitor_heart_outlined;
      case RecordKind.vaccination:
        return Icons.vaccines_outlined;
      case RecordKind.checkup:
        return Icons.favorite_border;
      case RecordKind.prescription:
        return Icons.medication_outlined;
      case RecordKind.other:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Medical Records'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () => _openAddRecordSheet(context),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_today_outlined,
                      size: 18, color: AppColors.textDark),
                  SizedBox(width: 8),
                  Text(
                    'Record History',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final record in data.records) ...[
                _RecordTile(
                  record: record,
                  icon: _iconFor(record.kind),
                  onView: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Text(record.title),
                        content: Text(
                          '${record.subtitle}\n\nDate: ${record.date}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final MedicalRecord record;
  final IconData icon;
  final VoidCallback onView;

  const _RecordTile({
    required this.record,
    required this.icon,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.infoBlueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(record.subtitle,
                    style: const TextStyle(color: AppColors.textGrey)),
                const SizedBox(height: 4),
                Text(
                  record.date,
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 12.5),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onView, child: const Text('View')),
        ],
      ),
    );
  }
}
