import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../shell.dart';
import '../widgets.dart';

/// Profile, password and preferences. Mirrors the guardian app's Profile
/// screen, with the details a clinician needs others to see.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    return PageBody(children: [
      const PageHeader(title: 'Settings', subtitle: 'Your profile, password and preferences.'),
      const _ProfileSection(),
      const SizedBox(height: 20),
      ResponsiveColumns(
        breakpoint: 980,
        children: [
          const _PasswordSection(),
          Panel(
            title: 'Preferences',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Time format'),
              const Text('Used for appointment times across the portal.',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
              const SizedBox(height: 10),
              OptionRow(
                label: '12-hour',
                detail: '2:30 PM',
                selected: !data.use24HourTime,
                onTap: () => data.setUse24HourTime(false),
              ),
              OptionRow(
                label: '24-hour',
                detail: '14:30',
                selected: data.use24HourTime,
                onTap: () => data.setUse24HourTime(true),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(
                  child: Text('Session timeout, sign-in activity and data handling are on the Security page.',
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12.5, height: 1.4)),
                ),
                TextLink('Open Security', onTap: () => Nav.instance.go(Section.security)),
              ]),
            ]),
          ),
        ],
      ),
    ]);
  }
}

// ---- professional profile ----------------------------------------------------

class _ProfileSection extends StatefulWidget {
  const _ProfileSection();

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  final data = ClinicData.instance;
  late final _name = TextEditingController(text: data.clinicianName);
  late final _title = TextEditingController(text: data.jobTitle);
  late final _clinic = TextEditingController(text: data.clinicName);
  late final _licence = TextEditingController(text: data.licenceNumber);
  late final _phone = TextEditingController(text: data.workPhone);
  late final _languages = TextEditingController(text: data.languages);
  late final _bio = TextEditingController(text: data.bio);
  late String _specialty = data.specialty;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _title, _clinic, _licence, _phone, _languages, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Your name is required.');
      return;
    }
    setState(() => _error = null);
    try {
      await data.updateProfile(
        name: _name.text.trim(),
        title: _title.text.trim(),
        specialty: _specialty,
        clinic: _clinic.text.trim(),
        licence: _licence.text.trim(),
        phone: _phone.text.trim(),
        languages: _languages.text.trim(),
        bio: _bio.text.trim(),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
  }

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget a, Widget b) => ResponsiveColumns(breakpoint: 560, gap: 14, children: [a, b]);
    void live(String _) => setState(() {});

    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pair(
        Field(label: 'Full name', controller: _name, onChanged: live),
        Field(label: 'Job title', hint: 'e.g. Consultant, Specialist', controller: _title, onChanged: live),
      ),
      const SizedBox(height: 14),
      pair(
        Select<String>(
          label: 'Specialty',
          value: _specialty,
          items: clinicianSpecialties,
          itemLabel: (s) => s,
          onChanged: (s) => setState(() => _specialty = s),
        ),
        Field(label: 'Licence number', hint: 'e.g. DHA-P-0123456', controller: _licence, onChanged: live),
      ),
      const SizedBox(height: 14),
      Field(label: 'Clinic / department', controller: _clinic, onChanged: live),
      const SizedBox(height: 14),
      pair(
        Field(label: 'Work phone', hint: '+971 ...', controller: _phone, onChanged: live),
        Field(label: 'Languages', controller: _languages, onChanged: live),
      ),
      const SizedBox(height: 14),
      Field(
        label: 'Short bio',
        hint: 'A sentence or two about you, e.g. your experience with early autism assessment.',
        controller: _bio,
        maxLines: 3,
        onChanged: live,
      ),
      const SizedBox(height: 14),
      KeyValue('Sign-in email', data.clinicianEmail),
      const Text('Your sign-in email is managed by your clinic administrator.',
          style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
      ],
      const SizedBox(height: 18),
      Align(alignment: Alignment.centerLeft, child: Btn('Update information', onPressed: _save)),
    ]);

    return Panel(
      title: 'Professional profile',
      caption: 'Families see your name and title on reviews; colleagues also see it on clinical notes '
          'and patient summaries.',
      child: ResponsiveColumns(
        breakpoint: 900,
        flex: const [3, 2],
        gap: 24,
        children: [form, _preview()],
      ),
    );
  }

  /// Live preview built from the form, so changes show before saving.
  Widget _preview() {
    final name = _name.text.trim().isEmpty ? 'Your name' : _name.text.trim();
    final title = _title.text.trim();
    final initials =
        name.replaceFirst('Dr. ', '').split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('HOW OTHERS SEE YOU',
            style:
                TextStyle(color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 14),
        Row(children: [
          Avatar(initials.toUpperCase(), size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppText.heading(17)),
              const SizedBox(height: 2),
              Text(title.isEmpty ? _specialty : '$title, $_specialty',
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (_clinic.text.trim().isNotEmpty) _line(_clinic.text.trim()),
        if (_licence.text.trim().isNotEmpty) _line('Licence ${_licence.text.trim()}'),
        if (_languages.text.trim().isNotEmpty) _line('Speaks ${_languages.text.trim()}'),
        if (_phone.text.trim().isNotEmpty) _line(_phone.text.trim()),
        if (_bio.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_bio.text.trim(), style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
        const SizedBox(height: 14),
        const Divider(color: AppColors.border),
        const SizedBox(height: 6),
        Text('On notes: "Reviewed by ${title.isEmpty ? name : '$name, $title'}"',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
      ]),
    );
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
      );
}

// ---- password ----------------------------------------------------------------

class _PasswordSection extends StatefulWidget {
  const _PasswordSection();

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  List<(String, bool)> get _rules {
    final p = _next.text;
    return [
      ('At least 12 characters', p.length >= 12),
      ('An uppercase and a lowercase letter', p.contains(RegExp('[A-Z]')) && p.contains(RegExp('[a-z]'))),
      ('At least one number', p.contains(RegExp('[0-9]'))),
      ('At least one symbol, e.g. ! ? # @', p.contains(RegExp(r'[^A-Za-z0-9]'))),
      ('Both new passwords match', p.isNotEmpty && p == _confirm.text),
    ];
  }

  Future<void> _change() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_rules.any((r) => !r.$2)) {
      setState(() => _error = 'The new password does not meet all the requirements yet.');
      return;
    }
    try {
      // The backend checks the current password and stores only a hash of the new one.
      await ClinicData.instance.changePassword(_current.text, _next.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (!mounted) return;
    _current.clear();
    _next.clear();
    _confirm.clear();
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
  }

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    void live(String _) => setState(() => _error = null);
    return Panel(
      title: 'Password',
      caption: data.passwordChangedAt == null
          ? 'Not changed since the account was issued.'
          : 'Last changed ${fmtAgo(data.passwordChangedAt!)}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PasswordField(label: 'Current password', controller: _current, onChanged: live),
        const SizedBox(height: 14),
        PasswordField(label: 'New password', controller: _next, onChanged: live),
        const SizedBox(height: 14),
        PasswordField(
            label: 'Confirm new password', controller: _confirm, onChanged: live, onSubmitted: (_) => _change()),
        const SizedBox(height: 14),
        for (final (label, ok) in _rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Dot(ok ? AppColors.success : AppColors.border, size: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: ok ? AppColors.success : AppColors.textGrey,
                        fontWeight: ok ? FontWeight.w700 : FontWeight.w500)),
              ),
            ]),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft, child: Btn('Change password', onPressed: _change)),
      ]),
    );
  }
}
