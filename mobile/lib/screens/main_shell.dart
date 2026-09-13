import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'medical_records_screen.dart';
import 'appointments_screen.dart';

/// Hosts the primary tabs behind a bottom navigation bar. The Figma
/// prototype didn't include a nav-bar frame, but the app needs one so the
/// separate screens (Dashboard / Records / Appointments) are all
/// reachable - this is the natural structure for a real ASD-Sense app.
/// Profile is intentionally left out of the tabs for now and can be added
/// back in later.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(onNavigateTab: goToTab),
      const MedicalRecordsScreen(),
      const AppointmentsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.textGrey,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: goToTab,
          backgroundColor: AppColors.surface,
          elevation: 3,
          height: 66,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.home, color: AppColors.primary),
              label: 'Home',
            ),
            NavigationDestination(
              icon:
                  Icon(Icons.description_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.description, color: AppColors.primary),
              label: 'Records',
            ),
            NavigationDestination(
              icon:
                  Icon(Icons.calendar_month_outlined, color: AppColors.textGrey),
              selectedIcon:
                  Icon(Icons.calendar_month, color: AppColors.primary),
              label: 'Appointments',
            ),
          ],
        ),
      ),
    );
  }
}
