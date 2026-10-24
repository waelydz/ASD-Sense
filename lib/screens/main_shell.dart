import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'records_screen.dart';
import 'detection_screen.dart';
import 'appointments_screen.dart';
import 'profile_screen.dart';

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
      HomeScreen(onNavigateTab: goToTab),
      RecordsScreen(onNavigateTab: goToTab),
      DetectionScreen(onNavigateTab: goToTab),
      AppointmentsScreen(onNavigateTab: goToTab),
      ProfileScreen(onNavigateTab: goToTab),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: Colors.transparent,
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            final selected = states.contains(MaterialState.selected);
            return TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primaryDark : AppColors.textGrey,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: goToTab,
          backgroundColor: AppColors.paper.withOpacity(0.97),
          elevation: 0,
          height: 68,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.home, color: AppColors.primaryDark),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.folder, color: AppColors.primaryDark),
              label: 'Records',
            ),
            NavigationDestination(
              icon: Icon(Icons.center_focus_weak_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.center_focus_strong, color: AppColors.primaryDark),
              label: 'Detection',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.calendar_month, color: AppColors.primaryDark),
              label: 'Appointments',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.person, color: AppColors.primaryDark),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
