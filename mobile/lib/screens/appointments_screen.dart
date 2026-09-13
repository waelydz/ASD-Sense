import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});

  void _openNewAppointmentSheet(BuildContext context) {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final locationController = TextEditingController();
    DateTime pickedDate = DateTime.now().add(const Duration(days: 7));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
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
                      'New Appointment',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    LabelledTextField(
                      label: "Doctor's Name",
                      hint: 'e.g. Dr. Amina Yousef',
                      controller: nameController,
                    ),
                    const SizedBox(height: 14),
                    LabelledTextField(
                      label: 'Role',
                      hint: 'e.g. Pediatrician',
                      controller: roleController,
                    ),
                    const SizedBox(height: 14),
                    LabelledTextField(
                      label: 'Location',
                      hint: 'e.g. Al Qassimi Hospital',
                      controller: locationController,
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () async {
                        final result = await showDatePicker(
                          context: ctx,
                          initialDate: pickedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (result != null) {
                          setSheetState(() => pickedDate = result);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: AppColors.textGrey),
                            const SizedBox(width: 10),
                            Text(_formatDate(pickedDate)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Add Appointment',
                      onPressed: () {
                        if (nameController.text.trim().isEmpty) return;
                        AppData.instance.addAppointment(
                          Appointment(
                            doctorName: nameController.text.trim(),
                            role: roleController.text.trim().isEmpty
                                ? 'Clinician'
                                : roleController.text.trim(),
                            date: _formatDate(pickedDate),
                            time: '10:00 AM',
                            location: locationController.text.trim().isEmpty
                                ? 'TBD'
                                : locationController.text.trim(),
                            isVirtual: locationController.text
                                .toLowerCase()
                                .contains('virtual'),
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

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _confirmCancel(BuildContext context, Appointment appt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel appointment?'),
        content: Text(
          'Are you sure you want to cancel your appointment with '
          '${appt.doctorName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () {
              AppData.instance.cancelAppointment(appt);
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel appointment',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, Appointment appt) async {
    final result = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (result != null) {
      AppData.instance.rescheduleAppointment(appt, _formatDate(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Appointments'),
        titleSpacing: 16,
        toolbarHeight: 64,
      ),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Manage your appointments',
                style: TextStyle(color: AppColors.textGrey),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Appointments',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openNewAppointmentSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (data.appointments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'No upcoming appointments.',
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  ),
                ),
              for (final appt in List<Appointment>.from(data.appointments)) ...[
                _AppointmentCard(
                  appt: appt,
                  onCancel: () => _confirmCancel(context, appt),
                  onReschedule: () => _reschedule(context, appt),
                  onJoin: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Joining virtual meeting... (demo)')),
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appt;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onJoin;

  const _AppointmentCard({
    required this.appt,
    required this.onCancel,
    required this.onReschedule,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoBlueBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  appt.isVirtual ? Icons.videocam : Icons.location_on,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appt.doctorName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(appt.role,
                      style: const TextStyle(color: AppColors.textGrey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(appt.date, style: const TextStyle(color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(appt.time, style: const TextStyle(color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(appt.location,
              style: const TextStyle(color: AppColors.textDark)),
          const SizedBox(height: 12),
          StatusBadge(text: appt.status),
          const SizedBox(height: 14),
          if (appt.isVirtual) ...[
            PrimaryButton(label: 'Join Meeting', onPressed: onJoin),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _PillButton(label: 'Reschedule', onTap: onReschedule),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PillButton(label: 'Cancel', onTap: onCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
