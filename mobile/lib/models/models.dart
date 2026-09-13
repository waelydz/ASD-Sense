class MedicalRecord {
  final String title;
  final String subtitle;
  final String date;
  final RecordKind kind;

  MedicalRecord({
    required this.title,
    required this.subtitle,
    required this.date,
    this.kind = RecordKind.other,
  });
}

enum RecordKind { screening, vaccination, checkup, prescription, other }

class Appointment {
  final String doctorName;
  final String role;
  String date;
  final String time;
  final String location;
  final bool isVirtual;
  String status;

  Appointment({
    required this.doctorName,
    required this.role,
    required this.date,
    required this.time,
    required this.location,
    this.isVirtual = false,
    this.status = 'Confirmed',
  });
}
