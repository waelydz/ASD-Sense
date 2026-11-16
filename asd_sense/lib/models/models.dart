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
  final int id;
  final String fileName;
  final RecordType type;
  final String date;

  MedicalRecord({
    required this.id,
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
  final int id;
  final CareCenter center;
  final DateTime scheduledAt;
  final String status;

  Appointment({required this.id, required this.center,
    required this.scheduledAt, required this.status});
}

class ScreeningSummary {
  final int id;
  final String modelName;
  final String predictedClass;
  final String date;

  /// The clinician's review, when there is one. Only the outcome is shared
  /// with families; the clinical note stays in the clinic.
  final String? reviewAction;
  final String? reviewerName;
  final String? reviewedAt;

  ScreeningSummary({required this.id, required this.modelName,
    required this.predictedClass, required this.date,
    this.reviewAction, this.reviewerName, this.reviewedAt});

  bool get isReviewed => reviewAction != null;

  /// What the family should do next, in plain words.
  String get nextStep => switch (reviewAction) {
        'refer_diagnostic' =>
          'A full developmental assessment is recommended. The clinic will contact you to arrange it.',
        'rescreen' => 'The clinician would like a new image. Please submit another screening.',
        'monitor' => 'No action is needed now. The clinician will look again at the next visit.',
        'no_further_action' => 'No further action is needed.',
        _ => 'Waiting for a clinician to review.',
      };
}

/// An update from the clinic: a screening was reviewed or an appointment's
/// status changed.
class AppNotification {
  final int id;
  final String title;
  final String body;
  final String createdAt;
  final bool isRead;

  AppNotification({required this.id, required this.title, required this.body,
    required this.createdAt, required this.isRead});
}
