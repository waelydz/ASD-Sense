import 'package:flutter/material.dart';
import '../models/models.dart';

class AppData extends ChangeNotifier {
  AppData._internal();
  static final AppData instance = AppData._internal();

  String guardianName = '';
  String email = '';
  String phone = '';

  bool pushNotifications = true;
  bool emailNotifications = false;

  void completeSignUp({
    required String name,
    required String email,
    required String phone,
  }) {
    guardianName = name;
    this.email = email;
    this.phone = phone;
    notifyListeners();
  }

  void updateGuardian({required String name, required String phone}) {
    guardianName = name;
    this.phone = phone;
    notifyListeners();
  }

  void setNotificationPrefs({bool? push, bool? emailPref}) {
    if (push != null) pushNotifications = push;
    if (emailPref != null) emailNotifications = emailPref;
    notifyListeners();
  }

  final List<Child> children = [];
  String? activeChildId;

  Child? get activeChild {
    if (activeChildId == null) return null;
    try {
      return children.firstWhere((c) => c.id == activeChildId);
    } catch (_) {
      return null;
    }
  }

  void addChild(String name, String age) {
    final child = Child(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      age: age,
    );
    children.add(child);
    recordsByChild[child.id] = [];
    activeChildId = child.id;
    notifyListeners();
  }

  void switchChild(String id) {
    activeChildId = id;
    notifyListeners();
  }

  final Map<String, List<MedicalRecord>> recordsByChild = {};

  List<MedicalRecord> get activeRecords =>
      activeChildId == null ? [] : (recordsByChild[activeChildId] ?? []);

  void addRecord(MedicalRecord record) {
    if (activeChildId == null) return;
    recordsByChild.putIfAbsent(activeChildId!, () => []);
    recordsByChild[activeChildId!]!.insert(0, record);
    notifyListeners();
  }

  void removeRecord(MedicalRecord record) {
    if (activeChildId == null) return;
    recordsByChild[activeChildId!]?.remove(record);
    notifyListeners();
  }

  final Map<String, Appointment> appointmentByChild = {};

  Appointment? get activeAppointment =>
      activeChildId == null ? null : appointmentByChild[activeChildId];

  void setAppointment(Appointment appt) {
    if (activeChildId == null) return;
    appointmentByChild[activeChildId!] = appt;
    notifyListeners();
  }

  final List<CareCenter> centers = [];
}
