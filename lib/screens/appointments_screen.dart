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
  CenterKind? _filter; // null = all

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

  Color _kindFg(CenterKind k) => switch (k) {
        CenterKind.hospital => AppColors.sage,
        CenterKind.clinic => AppColors.lavender,
        CenterKind.therapy => AppColors.sand,
      };

  Color _kindBg(CenterKind k) => switch (k) {
        CenterKind.hospital => AppColors.sageBg,
        CenterKind.clinic => AppColors.lavenderBg,
        CenterKind.therapy => AppColors.sandBg,
      };

  String _initials(String name) {
    final words = name.split(RegExp(r'\s+')).where((w) => RegExp(r'^[A-Za-z]').hasMatch(w));
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  Widget _buildFilters() {
    final options = <(String, CenterKind?)>[
      ('All', null),
      ('Hospitals', CenterKind.hospital),
      ('Clinics', CenterKind.clinic),
      ('Therapy', CenterKind.therapy),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (label, kind) = options[i];
          final selected = _filter == kind;
          return Material(
            color: selected ? AppColors.primary : AppColors.surface,
            shape: StadiumBorder(
              side: BorderSide(color: selected ? AppColors.primary : AppColors.inputBorder),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _filter = kind),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBooked(Appointment appt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('Appointment requested',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          Text(appt.center.name, style: AppText.heading(20, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            appt.center.address,
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
          if (appt.center.phone != null) ...[
            const SizedBox(height: 10),
            Text(
              'Call ${appt.center.phone} to confirm a time.',
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenterCard(CareCenter c, {required bool booked}) {
    final fg = _kindFg(c.kind);
    final bg = _kindBg(c.kind);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Text(_initials(c.name),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(c.address,
                        style: const TextStyle(
                            color: AppColors.textGrey, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(text: c.kindLabel, bg: bg, fg: fg),
              if (c.proximity.isNotEmpty)
                Pill(text: c.proximity, bg: AppColors.paper, fg: AppColors.textGrey),
            ],
          ),
          if (c.services.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(c.services.join('  ·  '),
                style: const TextStyle(color: AppColors.textDark, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  c.phone ?? 'Phone not listed',
                  style: TextStyle(
                    color: c.phone != null ? AppColors.textDark : AppColors.textFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: booked ? null : () => _book(c),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(booked ? 'Requested' : 'Book',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ),
            ],
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
          final q = _query.trim().toLowerCase();
          final results = data.centers.where((c) {
            if (_filter != null && c.kind != _filter) return false;
            if (q.isEmpty) return true;
            return c.name.toLowerCase().contains(q) ||
                c.address.toLowerCase().contains(q) ||
                c.services.any((s) => s.toLowerCase().contains(q));
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
                    _buildBooked(appt),
                    const SizedBox(height: 22),
                  ],
                  Text('Care near University City', style: AppText.heading(20)),
                  const SizedBox(height: 4),
                  const Text(
                    'Hospitals and clinics in and around University City, Sharjah.',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name, area, or service',
                      hintStyle: const TextStyle(color: AppColors.textFaint),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.inputBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFilters(),
                  const SizedBox(height: 16),
                  if (results.isEmpty)
                    SectionCard(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          Text('No matches found', style: AppText.heading(16)),
                          const SizedBox(height: 6),
                          const Text(
                            'Try a different name, area, or service.',
                            style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    )
                  else
                    for (final c in results) ...[
                      _buildCenterCard(c, booked: appt?.center.name == c.name),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 4),
                  const Text(
                    'Reference list from public listings. Please confirm services, '
                    'age groups and opening hours with each provider before visiting.',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.4),
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
