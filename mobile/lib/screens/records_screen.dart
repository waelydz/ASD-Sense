import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class RecordsScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  const RecordsScreen({super.key, required this.onNavigateTab});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  int _tabIndex = 0;
  final _tabs = const ['All files', 'Documents', 'Imaging'];

  Future<void> _openUploadSheet(BuildContext context) async {
    if (AppData.instance.activeChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a child profile first, from Home.')),
      );
      return;
    }

    RecordType type = RecordType.document;
    String? pickedFileName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: type == RecordType.imaging
                    ? ['jpg', 'jpeg', 'png', 'pdf']
                    : ['pdf', 'doc', 'docx'],
              );
              if (result != null && result.files.isNotEmpty) {
                setSheetState(() => pickedFileName = result.files.first.name);
              }
            }

            return Padding(
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
                    Text('Add medical record', style: AppText.heading(18)),
                    const SizedBox(height: 16),
                    const Text('Record type',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceCard(
                            label: 'Document',
                            selected: type == RecordType.document,
                            onTap: () => setSheetState(() => type = RecordType.document),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceCard(
                            label: 'Imaging',
                            selected: type == RecordType.imaging,
                            onTap: () => setSheetState(() => type = RecordType.imaging),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: pickFile,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: pickedFileName == null ? AppColors.inputBorder : AppColors.primary,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          color: pickedFileName == null ? AppColors.paper : AppColors.successBg,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              pickedFileName == null
                                  ? Icons.upload_file_outlined
                                  : Icons.check_circle,
                              color: pickedFileName == null
                                  ? AppColors.textGrey
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                pickedFileName ?? 'Choose a file to upload',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: pickedFileName == null
                                      ? AppColors.textFaint
                                      : AppColors.textDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Add record',
                      onPressed: pickedFileName == null
                          ? null
                          : () {
                              AppData.instance.addRecord(
                                MedicalRecord(
                                  fileName: pickedFileName!,
                                  type: type,
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
      },
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  IconData _iconFor(RecordType type) =>
      type == RecordType.document ? Icons.description_outlined : Icons.image_outlined;

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          final records = data.activeRecords;
          final filtered = _tabIndex == 0
              ? records
              : records.where((r) => r.type == RecordType.values[_tabIndex - 1]).toList();

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MainHeader(
                    title: 'Medical Records',
                    onProfileTap: () => widget.onNavigateTab(4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Records', style: AppText.heading(18)),
                      AppIconButton(
                        icon: Icons.add,
                        semanticLabel: 'Add record',
                        onPressed: () => _openUploadSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final selected = _tabIndex == i;
                        return ChoiceChip(
                          label: Text(_tabs[i]),
                          selected: selected,
                          onSelected: (_) => setState(() => _tabIndex = i),
                          backgroundColor: AppColors.surface,
                          selectedColor: AppColors.sageBg,
                          labelStyle: TextStyle(
                            color: selected ? AppColors.sage : AppColors.textGrey,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: selected ? AppColors.sageBg : AppColors.border,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    SectionCard(
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          const Icon(Icons.folder_open_outlined, size: 40, color: AppColors.textFaint),
                          const SizedBox(height: 14),
                          Text('No records yet', style: AppText.heading(16)),
                          const SizedBox(height: 6),
                          const Text(
                            'Upload a document or imaging report to keep it on hand.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    )
                  else
                    SectionCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (int i = 0; i < filtered.length; i++) ...[
                            if (i != 0) const Divider(height: 1, color: AppColors.border),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.lavenderBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_iconFor(filtered[i].type), color: AppColors.lavender, size: 18),
                              ),
                              title: Text(filtered[i].fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              subtitle: Text(
                                '${filtered[i].typeLabel} · ${filtered[i].date}',
                                style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
                                onPressed: () => AppData.instance.removeRecord(filtered[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Add medical record',
                    onPressed: () => _openUploadSheet(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
