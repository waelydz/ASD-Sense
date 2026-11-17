import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  final void Function(int tabIndex) onNavigateTab;
  const HomeScreen({super.key, required this.onNavigateTab});

  void _openChildSheet(BuildContext context) {
    final data = AppData.instance;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                    Text('Child profiles', style: AppText.heading(18)),
                    const SizedBox(height: 14),
                    if (data.children.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          "You haven't added a child profile yet.",
                          style: TextStyle(color: AppColors.textGrey),
                        ),
                      ),
                    for (final child in data.children)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            try {
                              await data.switchChild(child.id);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not save selected child.')),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: child.id == data.activeChildId
                                  ? AppColors.successBg
                                  : AppColors.paper,
                              border: Border.all(
                                color: child.id == data.activeChildId
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.lavenderBg,
                                  child: Icon(
                                    Icons.child_care,
                                    color: AppColors.lavender,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        child.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        child.age,
                                        style: const TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (child.id == data.activeChildId)
                                  const Icon(Icons.check_circle, color: AppColors.primary),
                                IconButton(
                                  tooltip: 'Edit profile',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: AppColors.textGrey,
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _openChildFormSheet(context, existing: child);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SecondaryButton(
                      label: 'Add a child profile',
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openChildFormSheet(context);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openChildFormSheet(BuildContext context, {Child? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    DateTime? dob = existing?.dateOfBirth;
    bool saving = false;
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 18, now.month, now.day);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
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
                      Text(
                        existing != null ? 'Edit child profile' : 'Add a child profile',
                        style: AppText.heading(18),
                      ),
                      const SizedBox(height: 16),
                      LabelledTextField(
                        label: "Child's name",
                        hint: 'Enter their name',
                        controller: nameController,
                      ),
                      const SizedBox(height: 14),
                      DateField(
                        label: 'Date of birth',
                        hint: 'Select date of birth',
                        value: dob,
                        firstDate: firstDate,
                        lastDate: now,
                        onChanged: (d) => setSheetState(() => dob = d),
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: existing != null ? 'Save changes' : 'Add child',
                        loading: saving,
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty || dob == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Enter your child's name and date of birth."),
                              ),
                            );
                            return;
                          }
                          if (saving) return;
                          setSheetState(() => saving = true);
                          try {
                            if (existing != null) {
                              await AppData.instance.updateChild(
                                existing.id,
                                name: name,
                                dateOfBirth: dob!,
                              );
                            } else {
                              await AppData.instance.addChild(name, dob!);
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e is ApiException
                                    ? e.message : 'Could not save child profile.')),
                              );
                            }
                          } finally {
                            if (ctx.mounted) setSheetState(() => saving = false);
                          }
                        },
                      ),
                      if (existing != null) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton(
                            onPressed: () => _confirmDeleteChild(ctx, context, existing),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              textStyle: const TextStyle(fontSize: 12.5),
                            ),
                            child: const Text('Delete this profile'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteChild(BuildContext sheetContext, BuildContext context, Child child) {
    showDialog(
      context: sheetContext,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Delete ${child.name}'s profile?"),
        content: const Text(
          'This profile can only be deleted if it has no screening or appointment '
          'history. Existing records will never be silently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await AppData.instance.removeChild(child.id);
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Child profile deleted.')),
                  );
                }
              } catch (e) {
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e is ApiException
                        ? e.message : 'Could not delete this child profile.')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          final child = data.activeChild;
          final appt = data.activeAppointment;
          final hasImaging = data.activeRecords.any((r) => r.type == RecordType.imaging);

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MainHeader(
                    title: 'Home',
                    eyebrow: child != null ? 'Viewing ${child.name}' : null,
                    onProfileTap: () => onNavigateTab(4),
                  ),
                  const SizedBox(height: 18),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openChildSheet(context),
                    child: SectionCard(
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.lavenderBg,
                            child: Icon(Icons.child_care, color: AppColors.lavender),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Child Profile',
                                  style: TextStyle(color: AppColors.textGrey),
                                ),
                                Text(
                                  child == null
                                      ? 'Add a child profile'
                                      : '${child.name}, ${child.age}',
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.unfold_more, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('Quick Actions', style: AppText.heading(18)),
                  const SizedBox(height: 12),
                  SectionCard(
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
                                  const Text(
                                    'Screening support',
                                    style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    hasImaging ? 'Screening submitted' : 'No submission yet',
                                    style: AppText.heading(19),
                                  ),
                                ],
                              ),
                            ),
                            Pill(
                              text: hasImaging ? 'Submitted' : 'Action needed',
                              bg: hasImaging ? AppColors.sageBg : AppColors.sandBg,
                              fg: hasImaging ? AppColors.sage : AppColors.sand,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        PrimaryButton(
                          label: 'Submit image for screening support',
                          onPressed: () => onNavigateTab(2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onNavigateTab(3),
                    child: SectionCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Upcoming appointment',
                                  style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  appt?.center.name ?? 'No appointment yet',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                    fontSize: 15,
                                  ),
                                ),
                                if (appt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    appt.center.address,
                                    style: const TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: ActionCard(
                          icon: Icons.folder_outlined,
                          title: 'Medical records',
                          onTap: () => onNavigateTab(1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionCard(
                          icon: Icons.event_available_outlined,
                          title: 'Book a visit',
                          onTap: () => onNavigateTab(3),
                        ),
                      ),
                    ],
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