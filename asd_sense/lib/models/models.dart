class Child {
  final String id;
  String name;
  DateTime dateOfBirth;

  Child({required this.id, required this.name, required this.dateOfBirth});

  /// Age worked out automatically from the date of birth.
  String get age {
    final now = DateTime.now();
    int months = (now.year - dateOfBirth.year) * 12 + (now.month - dateOfBirth.month);
    if (now.day < dateOfBirth.day) months -= 1;
    if (months < 1) return 'Under 1 month';
    if (months < 24) return months == 1 ? '1 month' : '$months months';
    final years = months ~/ 12;
    return '$years years';
  }

  String get dobLabel => '${dateOfBirth.day}/${dateOfBirth.month}/${dateOfBirth.year}';
}

enum RecordType { document, imaging }

class MedicalRecord {
  final String fileName;
  final RecordType type;
  final String date;

  MedicalRecord({
    required this.fileName,
    required this.type,
    required this.date,
  });

  String get typeLabel => type == RecordType.document ? 'Document' : 'Imaging report';
}

enum CenterKind { hospital, clinic, therapy }

class CareCenter {
  final String name;
  final String address;
  final String city;
  final CenterKind kind;

  /// Short, human-readable note on how close it is to University City.
  final String proximity;
  final List<String> services;
  final String? phone;

  CareCenter({
    required this.name,
    required this.address,
    required this.city,
    this.kind = CenterKind.clinic,
    this.proximity = '',
    this.services = const [],
    this.phone,
  });

  String get kindLabel {
    switch (kind) {
      case CenterKind.hospital:
        return 'Hospital';
      case CenterKind.clinic:
        return 'Clinic';
      case CenterKind.therapy:
        return 'Therapy centre';
    }
  }
}

class Appointment {
  final CareCenter center;

  Appointment({required this.center});
}
