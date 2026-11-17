import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../clinic_data.dart';
import '../models.dart';
import '../nav.dart';
import '../shell.dart';
import '../widgets.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  /// Monday of the week being shown.
  late DateTime _weekStart;
  bool _hideClosed = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  void _shift(int weeks) =>
      setState(() => _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final days = [for (var i = 0; i < 7; i++) DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i)];
    final weekEnd = days.last;
    final total = days.fold<int>(0, (n, d) => n + data.appointmentsOn(d).length);

    return PageBody(children: [
      PageHeader(
        title: 'Schedule',
        subtitle: 'Added by families in the ASD-Sense app.  ·  '
            'Week of ${fmtShortDate(_weekStart)} to ${fmtDate(weekEnd)}, $total appointment${total == 1 ? '' : 's'}',
      ),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Btn.secondary('Previous week', onPressed: () => _shift(-1)),
        Btn.secondary('This week', onPressed: () {
          final now = DateTime.now();
          setState(() => _weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1)));
        }),
        Btn.secondary('Next week', onPressed: () => _shift(1)),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _hideClosed = !_hideClosed),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: _hideClosed,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _hideClosed = v ?? false),
              ),
              const Flexible(child: Text('Hide cancelled and no-shows', style: TextStyle(fontSize: 13.5))),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      for (final d in days) _day(context, data, d),
    ]);
  }

  Widget _day(BuildContext context, ClinicData data, DateTime day) {
    var list = data.appointmentsOn(day);
    if (_hideClosed) {
      list = list.where((a) => a.status != VisitStatus.cancelled && a.status != VisitStatus.noShow).toList();
    }
    final isToday = sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        color: isToday ? const Color(0xFFF6FAF9) : null,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        title: fmtDayHeading(day),
        trailing: Text(list.isEmpty ? 'Free' : '${list.length}',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
        child: list.isEmpty
            ? const SizedBox.shrink()
            : Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  _ApptRow(list[i]),
                  if (i < list.length - 1) const Divider(height: 1, color: AppColors.border),
                ],
              ]),
      ),
    );
  }
}

class _ApptRow extends StatelessWidget {
  final ClinicAppointment a;
  const _ApptRow(this.a);

  @override
  Widget build(BuildContext context) {
    final data = ClinicScope.of(context);
    final p = data.patient(a.patientId);
    final end = a.scheduledAt.add(Duration(minutes: a.durationMinutes));
    final latest = p == null ? null : data.latestScreening(p.id);

    final time = SizedBox(
      width: 100,
      child: CellText(fmtTime(a.scheduledAt), strong: true, sub: 'to ${fmtTime(end)}'),
    );
    final who = InkWell(
      onTap: p == null ? null : () => Nav.instance.openPatient(p.id),
      child: CellText(p?.fullName ?? 'Unknown patient', strong: true, sub: '${a.type}  ·  ${a.location}'),
    );
    final context_ = latest == null
        ? const Text('No screenings', style: TextStyle(color: AppColors.textFaint, fontSize: 12.5))
        : Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Last screening', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
            ResultTag(latest.predictedClass),
          ]);
    final status = SizedBox(
      width: 160,
      child: Select<VisitStatus>(
        value: a.status,
        items: VisitStatus.values,
        itemLabel: (s) => s.label,
        onChanged: (s) => data.setAppointmentStatus(a, s),
      ),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 700) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [time, Expanded(child: who)]),
            const SizedBox(height: 8),
            context_,
            const SizedBox(height: 8),
            status,
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          time,
          Expanded(flex: 5, child: who),
          Expanded(flex: 3, child: context_),
          status,
        ]),
      );
    });
  }
}
