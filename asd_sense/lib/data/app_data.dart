import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/session_store.dart';

/// UI state is a cache of backend data, not its permanent source of truth.
class AppData extends ChangeNotifier {
  AppData._internal()
      : _api = ApiService(),
        _store = SecureSessionStore();

  /// Allows HTTP and secure-storage fakes in automated tests.
  AppData.testing({required ApiService api, required SessionStore store})
      : _api = api,
        _store = store;

  static final AppData instance = AppData._internal();
  final ApiService _api;
  final SessionStore _store;
  String? _token;
  int? _userId;

  bool get isSignedIn => _token != null && _userId != null;
  String guardianName = '';
  String email = '';
  String phone = '';

  bool pushNotifications = true;
  bool emailNotifications = false;

  final List<Child> children = [];
  String? activeChildId;

  Child? get activeChild {
    if (activeChildId == null) return null;
    for (final child in children) {
      if (child.id == activeChildId) return child;
    }
    return null;
  }

  static Child _parseChild(Map<String, dynamic> row) {
    final firstName = (row['first_name'] as String).trim();
    final lastName = (row['last_name'] as String?)?.trim();
    return Child(
      id: (row['child_id'] as int).toString(),
      name: lastName == null || lastName.isEmpty
          ? firstName
          : '$firstName $lastName',
      dateOfBirth: DateTime.parse(row['date_of_birth'] as String),
    );
  }

  void _setAccount(Map<String, dynamic> account) {
    _userId = account['user_id'] as int;
    guardianName = (account['full_name'] as String?) ?? '';
    email = (account['email'] as String?) ?? '';
    phone = (account['phone'] as String?) ?? '';
  }

  void _setChildren(List<Map<String, dynamic>> rows, String? selectedId) {
    children
      ..clear()
      ..addAll(rows.map(_parseChild));
    final selectedStillExists = children.any((c) => c.id == selectedId);
    activeChildId = selectedStillExists
        ? selectedId
        : (children.isEmpty ? null : children.first.id);
    // Records and appointments are not yet synchronized; clear stale previews.
    recordsByChild.clear();
    appointmentByChild.clear();
    notifyListeners();
  }

  Future<void> _acceptSession(Map<String, dynamic> response,
      {required bool remember}) async {
    final token = response['access_token'] as String;
    final account = Map<String, dynamic>.from(response['user'] as Map);
    final userId = account['user_id'] as int;
    final remoteChildren = await _api.listChildren(token);
    final selected = await _store.readSelectedChild(userId);
    await _store.writeToken(remember ? token : null);
    _token = token;
    _setAccount(account);
    _setChildren(remoteChildren, selected);
  }

  Future<void> signIn(String email, String password,
      {required bool remember}) async {
    final response = await _api.login(email, password);
    await _acceptSession(response, remember: remember);
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await _api.register(
      name: name, email: email, phone: phone, password: password,
    );
    await _acceptSession(response, remember: true);
  }

  /// Restore the verified session on cold launch. Never display cached medical data
  /// without successfully verifying the token with the backend first.
  Future<bool> restoreSession() async {
    try {
      final token = await _store.readToken();
      if (token == null || token.isEmpty) return false;
      final account = await _api.me(token);
      final rows = await _api.listChildren(token);
      final userId = account['user_id'] as int;
      final selected = await _store.readSelectedChild(userId);
      _token = token;
      _setAccount(account);
      _setChildren(rows, selected);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _store.writeToken(null); // expired or revoked token
      }
      return false;
    } catch (_) {
      // Network unavailable or secure storage error; do not expose cached data.
      return false;
    }
  }

  String get _requiredToken {
    final token = _token;
    if (token == null) throw const ApiException('Please sign in first.', statusCode: 401);
    return token;
  }

  Future<void> refreshChildren() async {
    final rows = await _api.listChildren(_requiredToken);
    _setChildren(rows, activeChildId);
  }

  Future<void> addChild(String name, DateTime dateOfBirth) async {
    final row = await _api.createChild(_requiredToken, name.trim(), dateOfBirth);
    final child = _parseChild(row);
    children.add(child);
    activeChildId = child.id;
    notifyListeners();
    try {
      await _store.writeSelectedChild(_userId!, child.id);
    } catch (_) {
      // The profile was saved on the server; do not misreport it as failed.
    }
  }

  Future<void> updateChild(String id,
      {required String name, required DateTime dateOfBirth}) async {
    final index = children.indexWhere((c) => c.id == id);
    if (index < 0) throw const ApiException('Child profile not found.');
    // A date-only edit must not overwrite an existing separate last_name field.
    final changedName = children[index].name == name.trim() ? null : name.trim();
    final row = await _api.updateChild(_requiredToken, id, changedName, dateOfBirth);
    children[index] = _parseChild(row);
    notifyListeners();
  }

  Future<void> removeChild(String id) async {
    await _api.deleteChild(_requiredToken, id);
    children.removeWhere((c) => c.id == id);
    recordsByChild.remove(id);
    appointmentByChild.remove(id);
    if (activeChildId == id) {
      activeChildId = children.isEmpty ? null : children.first.id;
      notifyListeners();
      try {
        await _store.writeSelectedChild(_userId!, activeChildId);
      } catch (_) {
        // Child deletion succeeded on the server; leave selection for re-entry.
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> switchChild(String id) async {
    if (!children.any((c) => c.id == id) || _userId == null) return;
    await _store.writeSelectedChild(_userId!, id);
    activeChildId = id;
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = _token;
    try {
      if (token != null) await _api.logout(token);
    } catch (_) {
      // Offline revocation is unavailable; token still expires server-side.
    }
    try {
      await _store.writeToken(null);
    } catch (_) {
      throw const ApiException('Could not clear local sign-in credentials. Retry logout.');
    }
    _token = null;
    _userId = null;
    guardianName = '';
    email = '';
    phone = '';
    children.clear();
    activeChildId = null;
    recordsByChild.clear();
    appointmentByChild.clear();
    notifyListeners();
  }

  /// Guardian profile editing and notification preferences remain local-only
  /// until their own authenticated backend persistence endpoint is implemented.
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
