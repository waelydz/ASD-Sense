import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'sign_in_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _editField(
    BuildContext context, {
    required String title,
    required String initialValue,
    required void Function(String value) onSave,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _openNotificationSettings(BuildContext context) {
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
                  const Text('Notification Settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    title: const Text('Push Notifications'),
                    subtitle: const Text('Appointment reminders & results'),
                    value: data.pushNotifications,
                    onChanged: (v) {
                      data.setNotificationPrefs(push: v);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    title: const Text('Email Notifications'),
                    subtitle: const Text('Weekly summaries'),
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

  @override
  Widget build(BuildContext context) {
    final data = AppData.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.black87,
                      child: Text(
                        data.guardianName.isNotEmpty
                            ? data.guardianName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.guardianName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text('Legal Guardian',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsGroup(
                      title: 'Account Information',
                      children: [
                        _SettingsTile(
                          title: 'Email',
                          subtitle: data.email,
                          onTap: () => _editField(
                            context,
                            title: 'Email',
                            initialValue: data.email,
                            keyboardType: TextInputType.emailAddress,
                            onSave: (v) {
                              if (v.isNotEmpty) {
                                data.updateProfileField(email: v);
                              }
                            },
                          ),
                        ),
                        _SettingsTile(
                          title: 'Phone Number',
                          subtitle: data.phone,
                          onTap: () => _editField(
                            context,
                            title: 'Phone Number',
                            initialValue: data.phone,
                            keyboardType: TextInputType.phone,
                            onSave: (v) {
                              if (v.isNotEmpty) {
                                data.updateProfileField(phone: v);
                              }
                            },
                          ),
                        ),
                        _SettingsTile(
                          title: 'Change Password',
                          subtitle: 'Update your password',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Password change flow (demo)')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SettingsGroup(
                      title: 'Child Profile',
                      children: [
                        _SettingsTile(
                          title: data.childName,
                          subtitle: 'Age: ${data.childAge}',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Open child profile (demo)')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SettingsGroup(
                      title: 'Preferences',
                      children: [
                        _SettingsTile(
                          title: 'Notifications',
                          subtitle: 'Manage notification settings',
                          onTap: () => _openNotificationSettings(context),
                        ),
                        _SettingsTile(
                          title: 'Privacy & Security',
                          subtitle: 'Control your data and privacy',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Privacy & Security (demo)')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const SignInScreen()),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const Text('Log Out',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          for (int i = 0; i < children.length; i++) ...[
            if (i != 0) const Divider(height: 1, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13.5)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
    );
  }
}
