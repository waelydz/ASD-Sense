import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class AppointmentsScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  const AppointmentsScreen({super.key, required this.onNavigateTab});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _book(CareCenter center) {
    if (AppData.instance.activeChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a child profile first, from Home.')),
      );
      return;
    }
    AppData.instance.setAppointment(Appointment(center: center));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Appointment requested at ${center.name}.')),
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
          final q = _query.trim().toLowerCase();
          final results = q.isEmpty
              ? data.centers
              : data.centers.where((c) {
                  return c.name.toLowerCase().contains(q) ||
                      c.address.toLowerCase().contains(q) ||
                      c.city.toLowerCase().contains(q);
                }).toList();

          final appt = data.activeAppointment;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MainHeader(
                    title: 'Appointments',
                    onProfileTap: () => widget.onNavigateTab(4),
                  ),
                  const SizedBox(height: 18),
                  if (appt != null) ...[
                    SectionCard(
                      bg: AppColors.successBg,
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.primaryDark),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Appointment requested',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark)),
                                const SizedBox(height: 2),
                                Text(
                                  '${appt.center.name} · ${appt.center.address}',
                                  style: const TextStyle(
                                      color: AppColors.primaryDark, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Text('Find a center', style: AppText.heading(18)),
                  const SizedBox(height: 4),
                  const Text(
                    'Search for a screening or care center near you.',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13.5),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name, area, or city',
                      hintStyle: const TextStyle(color: AppColors.textFaint),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: const BorderSide(color: AppColors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: const BorderSide(color: AppColors.inputBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (data.centers.isEmpty)
                    SectionCard(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          const Icon(Icons.location_city_outlined,
                              size: 36, color: AppColors.textFaint),
                          const SizedBox(height: 12),
                          Text('No centers added yet', style: AppText.heading(16)),
                          const SizedBox(height: 6),
                          const Text(
                            'Partner centers will appear here once added.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    )
                  else if (results.isEmpty)
                    SectionCard(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          const Icon(Icons.search_off, size: 36, color: AppColors.textFaint),
                          const SizedBox(height: 12),
                          Text('No matches found', style: AppText.heading(16)),
                          const SizedBox(height: 6),
                          const Text(
                            'Try a different name, area, or city.',
                            style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    )
                  else
                    for (final center in results) ...[
                      SectionCard(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.sageBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.local_hospital_outlined,
                                  color: AppColors.sage, size: 19),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(center.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${center.address} · ${center.city}',
                                    style: const TextStyle(
                                        color: AppColors.textGrey, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _book(center),
                              style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
                              child: const Text('Book'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
