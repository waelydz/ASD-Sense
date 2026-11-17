import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'clinic_data.dart';
import 'nav.dart';
import 'pages/overview_page.dart';
import 'pages/patient_detail_page.dart';
import 'pages/patients_page.dart';
import 'pages/review_queue_page.dart';
import 'pages/schedule_page.dart';
import 'pages/settings_page.dart';
import 'pages/screening_page.dart';
import 'pages/security_page.dart';
import 'pages/sign_in_page.dart';
import 'pages/system_page.dart';
import 'widgets.dart';

/// Signs out. The shell then returns to the sign-in page (see
/// [_ClinicianShellState._onDataChanged]), closing any open dialogs.
void signOutTo(BuildContext context, {String? message}) {
  ClinicData.instance.signOut(reason: message);
}

class ClinicianShell extends StatefulWidget {
  const ClinicianShell({super.key});

  @override
  State<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends State<ClinicianShell> {
  static const double _sidebarBreakpoint = 1000;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    // Automatic sign-out after inactivity (set on the Security page).
    _idleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final data = ClinicData.instance;
      if (mounted && data.idleTooLong) {
        signOutTo(context, message: 'You were signed out after ${data.autoSignOutMinutes} minutes of inactivity.');
      }
    });
    ClinicData.instance.addListener(_onDataChanged);
  }

  /// Leaves for the sign-in page whenever the session ends: the Sign out
  /// button, automatic sign-out, or the backend saying the session expired.
  void _onDataChanged() {
    final data = ClinicData.instance;
    if (data.isSignedIn || !mounted) return;
    data.removeListener(_onDataChanged);
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => SignInPage(message: data.signedOutReason),
        transitionDuration: Duration.zero,
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    ClinicData.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
    return ListenableBuilder(
      listenable: Listenable.merge([Nav.instance, ClinicData.instance]),
      builder: (context, _) {
        final content = _Content(key: ValueKey('${Nav.instance.section}-${Nav.instance.patientId}'));
        if (wide) {
          return Scaffold(
            backgroundColor: AppColors.paper,
            body: Row(
              children: [
                const SizedBox(width: 248, child: _Sidebar()),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.paper,
          drawer: const Drawer(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(),
            child: _Sidebar(inDrawer: true),
          ),
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
            title: Row(children: [
              Builder(
                builder: (ctx) => Btn.secondary('Menu', onPressed: () => Scaffold.of(ctx).openDrawer()),
              ),
              const SizedBox(width: 14),
              Text('ASD-Sense', style: AppText.heading(17, color: AppColors.primaryDark)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(Nav.instance.section.label,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textGrey, fontSize: 14)),
              ),
            ]),
          ),
          body: content,
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Nav.instance;
    switch (nav.section) {
      case Section.overview:
        return const OverviewPage();
      case Section.queue:
        return const ReviewQueuePage();
      case Section.patients:
        return nav.patientId == null ? const PatientsPage() : PatientDetailPage(patientId: nav.patientId!);
      case Section.schedule:
        return const SchedulePage();
      case Section.screening:
        return const ScreeningPage();
      case Section.system:
        return const SystemPage();
      case Section.settings:
        return const SettingsPage();
      case Section.security:
        return const SecurityPage();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final bool inDrawer;
  const _Sidebar({this.inDrawer = false});

  @override
  Widget build(BuildContext context) {
    // Listen directly: the sidebar is a const widget, so the parent's rebuilds
    // don't reach it. Without this the highlight never moved off Overview.
    return ListenableBuilder(
      listenable: Listenable.merge([Nav.instance, ClinicData.instance]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final data = ClinicData.instance;
    final nav = Nav.instance;
    final pending = data.pendingReview.length;
    final today = data.appointmentsOn(DateTime.now()).length;

    void go(Section s) {
      if (inDrawer) Navigator.of(context).pop();
      nav.go(s);
    }

    return Container(
      color: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 4),
              child: Text('ASD-Sense', style: AppText.heading(21, color: AppColors.primaryDark)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Text('Clinician portal', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
            ),
            // The menu scrolls on short windows; the account footer stays pinned.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _group('Work'),
                  _item(Section.overview, nav, go),
                  _item(Section.queue, nav, go, count: pending),
                  _item(Section.patients, nav, go),
                  _item(Section.schedule, nav, go, count: today),
                  const SizedBox(height: 16),
                  _group('Tools'),
                  _item(Section.screening, nav, go),
                  _item(Section.system, nav, go),
                  const SizedBox(height: 16),
                  _group('Account'),
                  _item(Section.settings, nav, go),
                  _item(Section.security, nav, go),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
              child: Row(
                children: [
                  Avatar(_initials(data.clinicianName), size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data.clinicianName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text(data.clinicianEmail,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.textGrey),
                    onPressed: () => signOutTo(context),
                    child: const Text('Sign out', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.replaceFirst('Dr. ', '').split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }

  Widget _group(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _item(Section s, Nav nav, void Function(Section) go, {int count = 0}) {
    final active = nav.section == s;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? AppColors.sageBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => go(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: active ? AppColors.primary : Colors.transparent, width: 3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppColors.primaryDark : AppColors.textDark,
                      )),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.textDark,
                        )),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scrollable, width-limited page body used by every section.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 40, narrow ? 20 : 36, narrow ? 16 : 40, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
