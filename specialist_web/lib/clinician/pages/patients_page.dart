import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../api_client.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../shell.dart';
import '../widgets.dart';

const _statusFilters = [
  'All patients',
  'Awaiting review',
  'Referred',
  'Rescreen',
  'Monitoring',
  'Closed',
  'No screenings'
];

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final _search = TextEditingController();
  String _status = _statusFilters.first;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final q = _search.text.trim().toLowerCase();
    final list = data.patients.where((p) {
      if (q.isNotEmpty && !p.fullName.toLowerCase().contains(q) && !p.guardianName.toLowerCase().contains(q)) {
        return false;
      }
      return _status == _statusFilters.first || data.caseStatus(p.id) == _status;
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return PageBody(children: [
      PageHeader(
        title: 'Patients',
        subtitle: '${data.patients.length} children',
        actions: [Btn('Add patient', onPressed: () => _showAddPatient(context))],
      ),
      Wrap(spacing: 14, runSpacing: 12, children: [
        SizedBox(
          width: 320,
          child: Field(
            label: '',
            hint: 'Search by child or guardian',
            controller: _search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          width: 200,
          child: Select<String>(
            value: _status,
            items: _statusFilters,
            itemLabel: (s) => s,
            onChanged: (s) => setState(() => _status = s),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No patients match.', style: TextStyle(color: AppColors.textGrey)),
              )
            : Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  _PatientRow(list[i]),
                  if (i < list.length - 1) const Divider(height: 1, color: AppColors.border),
                ],
              ]),
      ),
    ]);
  }
}

class _PatientRow extends StatelessWidget {
  final Patient p;
  const _PatientRow(this.p);

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final latest = data.latestScreening(p.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Nav.instance.openPatient(p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 640;
          return Row(children: [
            Avatar(p.initials, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(wide ? '${p.ageLabel}  ·  Guardian: ${p.guardianName}' : p.ageLabel,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textGrey)),
              ]),
            ),
            if (wide)
              SizedBox(
                width: 190,
                child: Text(latest == null ? 'Not screened yet' : 'Last screened ${fmtAgo(latest.date)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textGrey)),
              ),
            const SizedBox(width: 12),
            CaseStatusTag(data.caseStatus(p.id)),
          ]);
        }),
      ),
    );
  }
}

Future<void> _showAddPatient(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _AddPatientDialog());
}

class _AddPatientDialog extends StatefulWidget {
  const _AddPatientDialog();

  @override
  State<_AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<_AddPatientDialog> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  DateTime? _dob;
  String _sex = 'Not recorded';
  String _referral = 'Paediatrician';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _guardian, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 2, now.month, now.day),
      firstDate: DateTime(now.year - 18),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_first.text.trim().isEmpty || _dob == null || _guardian.text.trim().isEmpty) {
      setState(() => _error = 'First name, date of birth and guardian name are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Patient? p;
    try {
      p = await ClinicData.instance.addPatient(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        dateOfBirth: _dob!,
        sex: _sex,
        guardianName: _guardian.text.trim(),
        guardianPhone: _phone.text.trim(),
        guardianEmail: _email.text.trim(),
        referralSource: _referral,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (p != null) Nav.instance.openPatient(p.id);
  }

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget a, Widget b) => ResponsiveColumns(breakpoint: 520, gap: 14, children: [a, b]);
    return Dialog(
      backgroundColor: AppColors.paper,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add patient', style: AppText.heading(22)),
              const SizedBox(height: 20),
              pair(Field(label: 'First name', controller: _first), Field(label: 'Last name', controller: _last)),
              const SizedBox(height: 14),
              pair(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const FieldLabel('Date of birth'),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _pickDob,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(_dob == null ? 'Choose date' : fmtDate(_dob!),
                          style: TextStyle(
                              color: _dob == null ? AppColors.textFaint : AppColors.textDark,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ]),
                Select<String>(
                  label: 'Sex',
                  value: _sex,
                  items: const ['Not recorded', 'Female', 'Male', 'Other'],
                  itemLabel: (s) => s,
                  onChanged: (s) => setState(() => _sex = s),
                ),
              ),
              const SizedBox(height: 14),
              pair(
                Field(label: 'Guardian name', controller: _guardian),
                Select<String>(
                  label: 'Referred by',
                  value: _referral,
                  items: const [
                    'Paediatrician',
                    'ASD-Sense guardian app',
                    'Nursery teacher',
                    'Speech therapist',
                    'Self-referral',
                    'Other',
                  ],
                  itemLabel: (s) => s,
                  onChanged: (s) => setState(() => _referral = s),
                ),
              ),
              const SizedBox(height: 14),
              pair(Field(label: 'Guardian phone', controller: _phone),
                  Field(label: 'Guardian email', controller: _email)),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 22),
              Wrap(spacing: 10, runSpacing: 10, children: [
                Btn('Add patient', onPressed: _save, loading: _saving),
                Btn.secondary('Cancel', onPressed: () => Navigator.of(context).pop()),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
