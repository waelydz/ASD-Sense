import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'privacy_security_screen.dart';

class ProfileScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  const ProfileScreen({super.key, required this.onNavigateTab});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _nameController = TextEditingController(text: AppData.instance.guardianName);
  late final _phoneController = TextEditingController(text: AppData.instance.phone);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _update() {
    AppData.instance.updateGuardian(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
    );
  }

  void _openNotificationSettings() {
    final data = AppData.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Notification settings', style: AppText.heading(18)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    title: const Text('Push notifications'),
                    subtitle: const Text('Appointment reminders and results'),
                    value: data.pushNotifications,
                    onChanged: (v) {
                      data.setNotificationPrefs(push: v);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    title: const Text('Email notifications'),
                    subtitle: const Text('Account and appointment updates'),
                    value: data.emailNotifications,
                    onChanged: (v) {
                      data.setNotificationPrefs(emailPref: v);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete account?'),
        content: const Text('This will permanently remove your account and saved data.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Delete account', style: TextStyle(color: AppColors.danger)),
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
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MainHeader(title: 'Profile', onProfileTap: () {}),
                  const SizedBox(height: 18),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabelledTextField(
                          label: 'Name',
                          hint: 'Your name',
                          controller: _nameController,
                        ),
                        const SizedBox(height: 16),
                        LabelledTextField(
                          label: 'Phone',
                          hint: 'Your phone number',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 18),
                        PrimaryButton(label: 'Update information', onPressed: _update),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Preferences', style: AppText.heading(16)),
                  const SizedBox(height: 10),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          leading: const Icon(Icons.notifications_outlined,
                              color: AppColors.textDark),
                          title: const Text('Notifications',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          subtitle: const Text('Manage notification preferences',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
                          onTap: _openNotificationSettings,
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          leading: const Icon(Icons.shield_outlined, color: AppColors.textDark),
                          title: const Text('Privacy & Security',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          subtitle: const Text('Control your data and privacy',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PrivacySecurityScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SecondaryButton(
                    label: 'Change password',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password update flow coming soon.')),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DangerButton(label: 'Delete account', onPressed: _confirmDelete),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
