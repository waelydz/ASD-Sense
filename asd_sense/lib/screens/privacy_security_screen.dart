import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconButton(
                    icon: Icons.arrow_back,
                    semanticLabel: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Text('Privacy & Security', style: AppText.heading(21)),
                ],
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.lock_outline,
                title: 'Data protection',
                body:
                    "Your child's medical records, screening images, and "
                    'appointment details are encrypted in transit and at '
                    'rest, and are only accessible from your account.',
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.visibility_outlined,
                title: "Who can see your child's information",
                body:
                    'Only you, as the account holder, can view your '
                    "child's profile and records, unless you choose to "
                    'share them with a clinician through the app.',
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.image_outlined,
                title: 'Screening images',
                body:
                    'Images submitted for screening support are used only '
                    'to generate your evaluation result and are not '
                    'retained longer than necessary to produce that result.',
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.manage_accounts_outlined,
                title: 'Your rights',
                body:
                    'You can review, update, or delete your account and '
                    "your children's data at any time from the Profile "
                    'tab.',
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.mail_outline,
                title: 'Questions about privacy',
                body:
                    'If you have questions about how your data is '
                    'handled, reach out through the support options in '
                    'your account settings.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required IconData icon, required String title, required String body}) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sageBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.sage, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(color: AppColors.textGrey, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
