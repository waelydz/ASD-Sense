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

  void addChild(String name, DateTime dateOfBirth) {
    final child = Child(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      dateOfBirth: dateOfBirth,
    );
    children.add(child);
    recordsByChild[child.id] = [];
    activeChildId = child.id;
    notifyListeners();
  }

  void updateChild(String id, {required String name, required DateTime dateOfBirth}) {
    final index = children.indexWhere((c) => c.id == id);
    if (index == -1) return;
    children[index].name = name;
    children[index].dateOfBirth = dateOfBirth;
    notifyListeners();
  }

  void removeChild(String id) {
    children.removeWhere((c) => c.id == id);
    recordsByChild.remove(id);
    appointmentByChild.remove(id);
    if (activeChildId == id) {
      activeChildId = children.isEmpty ? null : children.first.id;
    }
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

  /// Reference list of care providers in and around University City, Sharjah.
  /// Details come from public listings; confirm services and hours before visiting.
  final List<CareCenter> centers = [
    CareCenter(
      name: 'University Hospital Sharjah',
      address: 'University Street, University City',
      city: 'Sharjah',
      kind: CenterKind.hospital,
      proximity: 'In University City',
      services: ['Paediatrics', 'Neurology', 'Psychiatry', 'Speech therapy'],
      phone: '+971 6 505 8555',
    ),
    CareCenter(
      name: 'Medcare Medical Centre, Al Zahia',
      address: 'Al Zahia Uptown, University City Rd, Muwaileh',
      city: 'Sharjah',
      kind: CenterKind.clinic,
      proximity: 'On University City Road',
      services: ['Paediatrics', 'Family medicine', 'Physiotherapy'],
      phone: '800 633 2273',
    ),
    CareCenter(
      name: 'Dar Al Aman Medical Centre',
      address: 'University City Road, Muwaileh Commercial',
      city: 'Sharjah',
      kind: CenterKind.clinic,
      proximity: 'On University City Road',
      services: ['General medicine', 'Dentistry'],
    ),
    CareCenter(
      name: 'Al Hawas Hearing & Speech Centre',
      address: 'University Road, Muwaileh Commercial',
      city: 'Sharjah',
      kind: CenterKind.therapy,
      proximity: 'Near University City',
      services: ['Speech therapy', 'Hearing rehabilitation'],
    ),
    CareCenter(
      name: 'Aster Muwaileh Medical Center',
      address: 'Bin Tharyem 8, Muwaileh',
      city: 'Sharjah',
      kind: CenterKind.clinic,
      proximity: 'Muwaileh, nearby',
      services: ['General medicine', 'Dentistry'],
    ),
    CareCenter(
      name: 'Al Qassimi Hospital',
      address: 'Wasit Street, Al Khazamiya',
      city: 'Sharjah',
      kind: CenterKind.hospital,
      proximity: 'Central Sharjah',
      services: ['Emergency care', 'Specialist referrals'],
      phone: '+971 6 518 8888',
    ),
  ];
}
