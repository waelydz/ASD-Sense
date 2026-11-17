/// Data types for the clinician web portal. Each one mirrors a backend table
/// and is built from the GET /clinic/state snapshot.
library;

import '../data/http_api.dart';

export '../data/http_api.dart' show parseBackendDate;

class Patient {
  /// `Child_Profiles.child_id` in the backend. [id] is the same number as text.
  final int childId;
  String get id => '$childId';

  String firstName;
  String lastName;
  DateTime dateOfBirth;
  String sex;
  String guardianName;
  String guardianPhone;
  String guardianEmail;
  String referralSource;

  Patient({
    required this.childId,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.sex,
    required this.guardianName,
    required this.guardianPhone,
    required this.guardianEmail,
    required this.referralSource,
  });

  factory Patient.fromApi(Map<String, dynamic> row) {
    const sexLabels = {'female': 'Female', 'male': 'Male', 'other': 'Other'};
    String orDash(Object? v) => (v as String?)?.isNotEmpty == true ? v as String : '-';
    return Patient(
      childId: row['child_id'] as int,
      firstName: row['first_name'] as String,
      lastName: (row['last_name'] as String?) ?? '',
      dateOfBirth: DateTime.parse(row['date_of_birth'] as String),
      sex: sexLabels[row['sex']] ?? 'Not recorded',
      guardianName: orDash(row['guardian_name']),
      guardianPhone: orDash(row['guardian_phone']),
      guardianEmail: orDash(row['guardian_email']),
      referralSource: orDash(row['referral_source']),
    );
  }

  String get fullName => lastName.isEmpty ? firstName : '$firstName $lastName';

  String get initials {
    final a = firstName.isNotEmpty ? firstName[0] : '';
    final b = lastName.isNotEmpty ? lastName[0] : '';
    return (a + b).toUpperCase();
  }

  int get ageInMonths {
    final now = DateTime.now();
    var months = (now.year - dateOfBirth.year) * 12 + (now.month - dateOfBirth.month);
    if (now.day < dateOfBirth.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// Months under two years, then years and months.
  String get ageLabel {
    final m = ageInMonths;
    if (m < 24) return '$m months';
    return m % 12 == 0 ? '${m ~/ 12} yrs' : '${m ~/ 12} yrs ${m % 12} mo';
  }
}

enum ScreeningModality { gesture, facial }

extension ScreeningModalityX on ScreeningModality {
  String get label => this == ScreeningModality.gesture ? 'Hand gesture' : 'Facial';
  String get endpoint => '/api/clinic/predict/${this == ScreeningModality.gesture ? 'gesture' : 'facial'}';
}

class Screening {
  final int id;
  final String patientId;
  final DateTime date;
  final String modelName;
  final String? modelVersion;

  /// One of `autistic`, `non_autistic`, `inconclusive` (backend CHECK constraint).
  final String predictedClass;
  final double? autismProbability;
  final double? confidence;
  final String? imageReference;

  /// The backend stores the routing tier in `notes`.
  final String? routing;

  /// The screened image is kept by the backend and can be shown.
  final bool hasImage;

  Screening({
    required this.id,
    required this.patientId,
    required this.date,
    required this.modelName,
    this.modelVersion,
    required this.predictedClass,
    this.autismProbability,
    this.confidence,
    this.imageReference,
    this.routing,
    this.hasImage = false,
  });

  /// Reviews are looked up by this.
  String get key => '$id';

  bool get isFlagged => predictedClass == 'autistic';
  bool get isInconclusive => predictedClass == 'inconclusive';
  bool get wasEscalated => (routing ?? '').toLowerCase().contains('escalated');
  bool get isSimulated => modelName.toLowerCase().startsWith('simulated');

  ScreeningModality get modality =>
      modelName.toLowerCase().contains('facial') ? ScreeningModality.facial : ScreeningModality.gesture;

  String get resultLabel {
    switch (predictedClass) {
      case 'autistic':
        return 'Flagged';
      case 'non_autistic':
        return 'Not flagged';
      default:
        return 'Inconclusive';
    }
  }

  /// Higher means look at it sooner.
  double get priority {
    final p = autismProbability ?? 0.5;
    if (isFlagged) return 2 + p;
    if (isInconclusive) return 1 + p;
    return p;
  }

  factory Screening.fromApi(Map<String, dynamic> row) {
    return Screening(
      id: row['screening_id'] as int,
      patientId: '${row['child_id']}',
      date: parseBackendDate(row['screening_date'] as String?),
      modelName: (row['model_name'] as String?) ?? 'unknown',
      modelVersion: row['model_version'] as String?,
      predictedClass: (row['predicted_class'] as String?) ?? 'inconclusive',
      autismProbability: (row['autism_probability'] as num?)?.toDouble(),
      confidence: (row['confidence'] as num?)?.toDouble(),
      imageReference: row['image_reference'] as String?,
      routing: row['notes'] as String?,
      hasImage: row['has_image'] == true,
    );
  }
}

/// A document or imaging report the family uploaded in the guardian app.
class FamilyRecord {
  /// `Medical_Records.record_id` in the backend.
  final int id;
  final String patientId;
  final String fileName;

  /// `document` or `imaging`.
  final String type;
  final DateTime addedAt;

  /// False for records listed before the app uploaded the files themselves.
  final bool hasFile;

  FamilyRecord({
    required this.id,
    required this.patientId,
    required this.fileName,
    required this.type,
    required this.addedAt,
    required this.hasFile,
  });

  String get typeLabel => type == 'document' ? 'Document' : 'Imaging report';

  factory FamilyRecord.fromApi(Map<String, dynamic> row) {
    return FamilyRecord(
      id: row['record_id'] as int,
      patientId: '${row['child_id']}',
      fileName: row['file_name'] as String,
      type: row['record_type'] as String,
      addedAt: parseBackendDate(row['created_at'] as String?),
      hasFile: row['has_file'] == 1,
    );
  }
}

enum ClinicalFinding { agree, disagree, needsMoreInfo }

extension ClinicalFindingX on ClinicalFinding {
  /// Value of `Screening_Reviews.finding` in the backend.
  String get apiValue => const ['agree', 'disagree', 'needs_more_info'][index];

  String get label {
    switch (this) {
      case ClinicalFinding.agree:
        return 'Agree with model';
      case ClinicalFinding.disagree:
        return 'Disagree with model';
      case ClinicalFinding.needsMoreInfo:
        return 'Cannot judge from this image';
    }
  }
}

enum RecommendedAction { referDiagnostic, rescreen, monitor, noFurtherAction }

extension RecommendedActionX on RecommendedAction {
  /// Value of `Screening_Reviews.action` in the backend.
  String get apiValue => const ['refer_diagnostic', 'rescreen', 'monitor', 'no_further_action'][index];

  String get label {
    switch (this) {
      case RecommendedAction.referDiagnostic:
        return 'Refer for full diagnostic assessment';
      case RecommendedAction.rescreen:
        return 'Request a new image / rescreen';
      case RecommendedAction.monitor:
        return 'Monitor, review at next visit';
      case RecommendedAction.noFurtherAction:
        return 'No further action';
    }
  }

  String get short {
    switch (this) {
      case RecommendedAction.referDiagnostic:
        return 'Referred';
      case RecommendedAction.rescreen:
        return 'Rescreen';
      case RecommendedAction.monitor:
        return 'Monitoring';
      case RecommendedAction.noFurtherAction:
        return 'Closed';
    }
  }
}

class ClinicalReview {
  final String screeningKey;
  final ClinicalFinding finding;
  final RecommendedAction action;
  final String note;
  final String reviewer;
  final DateTime reviewedAt;

  ClinicalReview({
    required this.screeningKey,
    required this.finding,
    required this.action,
    required this.note,
    required this.reviewer,
    required this.reviewedAt,
  });

  factory ClinicalReview.fromApi(Map<String, dynamic> row) {
    return ClinicalReview(
      screeningKey: '${row['screening_id']}',
      finding: ClinicalFinding.values.firstWhere((f) => f.apiValue == row['finding']),
      action: RecommendedAction.values.firstWhere((a) => a.apiValue == row['action']),
      note: (row['note'] as String?) ?? '',
      reviewer: row['reviewer_name'] as String,
      reviewedAt: parseBackendDate(row['reviewed_at'] as String?),
    );
  }
}

/// Same values as the backend `Appointments.status` CHECK constraint.
enum VisitStatus { scheduled, confirmed, completed, cancelled, noShow }

extension VisitStatusX on VisitStatus {
  /// Value of `Appointments.status` in the backend.
  String get apiValue => const ['scheduled', 'confirmed', 'completed', 'cancelled', 'no_show'][index];

  String get label {
    switch (this) {
      case VisitStatus.scheduled:
        return 'Scheduled';
      case VisitStatus.confirmed:
        return 'Confirmed';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.cancelled:
        return 'Cancelled';
      case VisitStatus.noShow:
        return 'No show';
    }
  }
}

class ClinicAppointment {
  /// `Appointments.appointment_id` in the backend.
  final int id;
  final String patientId;
  DateTime scheduledAt;
  int durationMinutes;
  String type;
  String location;
  VisitStatus status;
  String notes;

  ClinicAppointment({
    required this.id,
    required this.patientId,
    required this.scheduledAt,
    this.durationMinutes = 45,
    required this.type,
    required this.location,
    this.status = VisitStatus.scheduled,
    this.notes = '',
  });

  factory ClinicAppointment.fromApi(Map<String, dynamic> row) {
    return ClinicAppointment(
      id: row['appointment_id'] as int,
      patientId: '${row['child_id']}',
      scheduledAt: parseBackendDate(row['scheduled_at'] as String?),
      type: (row['appointment_type'] as String?) ?? 'Appointment',
      location: (row['location'] as String?) ?? '-',
      status: VisitStatus.values.firstWhere((s) => s.apiValue == row['status'], orElse: () => VisitStatus.scheduled),
      notes: (row['notes'] as String?) ?? '',
    );
  }
}

/// One line in the Security page's activity log.
class ActivityEntry {
  final DateTime at;
  final String text;
  ActivityEntry(this.at, this.text);
}

const clinicianSpecialties = [
  'Developmental paediatrics',
  'Child & adolescent psychiatry',
  'Clinical psychology',
  'Paediatric neurology',
  'Speech & language therapy',
  'Occupational therapy',
  'General paediatrics',
];

class BackendStatus {
  final bool online;
  final bool gestureMobileNet;
  final bool gestureVit;
  final bool facialMobileNet;
  final bool facialVit;
  final String? error;
  final DateTime checkedAt;

  BackendStatus({
    required this.online,
    this.gestureMobileNet = false,
    this.gestureVit = false,
    this.facialMobileNet = false,
    this.facialVit = false,
    this.error,
    required this.checkedAt,
  });
}

class ScreeningResult {
  final int screeningId;
  final String modelName;
  final String routing;
  final String predictedClass;
  final double autismProbability;
  final double confidence;

  ScreeningResult({
    required this.screeningId,
    required this.modelName,
    required this.routing,
    required this.predictedClass,
    required this.autismProbability,
    required this.confidence,
  });
}
