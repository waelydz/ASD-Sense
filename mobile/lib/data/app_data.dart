import 'package:flutter/material.dart';
import '../models/models.dart';

/// Very small in-memory "backend" for the prototype.
///
/// This is a single ChangeNotifier singleton that every screen listens to
/// (via AnimatedBuilder / ValueListenableBuilder wrappers). It's intentionally
/// simple - in a production app this would be replaced by a real state
/// management solution (Riverpod/Bloc/Provider) talking to an API.
class AppData extends ChangeNotifier {
  AppData._internal();
  static final AppData instance = AppData._internal();

  // ---- Profile -------------------------------------------------------
  String guardianName = 'Abdullah Ahmad';
  String email = 'u23100949@sharjah.ac.ae';
  String phone = '+971 500000000';
  String childName = 'Sarah Ahmad';
  String childAge = '3 years, 4 months';
  bool pushNotifications = true;
  bool emailNotifications = false;

  // ---- Medical records -------------------------------------------------
  final List<MedicalRecord> records = [
    MedicalRecord(
      title: 'Autism Screening',
      subtitle: 'Low Risk - 94.2% confidence',
      date: 'April 19, 2026',
      kind: RecordKind.screening,
    ),
    MedicalRecord(
      title: 'Autism Screening',
      subtitle: 'Low Risk - 92.8% confidence',
      date: 'April 15, 2026',
      kind: RecordKind.screening,
    ),
    MedicalRecord(
      title: 'MMR Vaccination',
      subtitle: 'Administered - No reactions',
      date: 'April 5, 2026',
      kind: RecordKind.vaccination,
    ),
    MedicalRecord(
      title: 'Annual Checkup',
      subtitle: 'Normal development - Healthy',
      date: 'March 20, 2026',
      kind: RecordKind.checkup,
    ),
    MedicalRecord(
      title: 'Vitamin D Supplement',
      subtitle: 'Prescribed by Dr. Wael',
      date: 'March 1, 2026',
      kind: RecordKind.prescription,
    ),
  ];

  void addRecord(MedicalRecord record) {
    records.insert(0, record);
    notifyListeners();
  }

  // ---- Appointments ------------------------------------------------------
  final List<Appointment> appointments = [
    Appointment(
      doctorName: 'Dr. Sewar Feras',
      role: 'Clinician',
      date: 'April 3rd, 2026',
      time: '10:00 AM',
      location: 'University of Sharjah Hospital',
    ),
    Appointment(
      doctorName: 'Dr. Syed Yahya',
      role: 'Pediatrician',
      date: 'April 15th, 2026',
      time: '5:00 PM',
      location: 'Virtual Meeting',
      isVirtual: true,
    ),
  ];

  int get pendingAssessments => 3;
  String get nextAppointmentDate =>
      appointments.isNotEmpty ? appointments.first.date : '-';

  void addAppointment(Appointment appt) {
    appointments.add(appt);
    notifyListeners();
  }

  void cancelAppointment(Appointment appt) {
    appointments.remove(appt);
    notifyListeners();
  }

  void rescheduleAppointment(Appointment appt, String newDate) {
    appt.date = newDate;
    notifyListeners();
  }

  void updateProfileField({
    String? email,
    String? phone,
  }) {
    if (email != null) this.email = email;
    if (phone != null) this.phone = phone;
    notifyListeners();
  }

  void setNotificationPrefs({bool? push, bool? emailPref}) {
    if (push != null) pushNotifications = push;
    if (emailPref != null) emailNotifications = emailPref;
    notifyListeners();
  }
}
