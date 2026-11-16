import 'dart:async';
import 'dart:typed_data';
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
    // Clear cached data before reloading it for the verified child.
    recordsByChild.clear();
    appointmentByChild.clear();
    screeningsByChild.clear();
    notifyListeners();
  }

  void _clearCachedIdentity() {
    stopNotificationPolling();
    notifications.clear();
    _token = null;
    _userId = null;
    guardianName = '';
    email = '';
    phone = '';
    children.clear();
    activeChildId = null;
    recordsByChild.clear();
    appointmentByChild.clear();
    screeningsByChild.clear();
    notifyListeners();
  }

  Future<void> _acceptSession(Map<String, dynamic> response,
      {required bool remember}) async {
    try {
      final token = response['access_token'] as String;
      final account = Map<String, dynamic>.from(response['user'] as Map);
      final userId = account['user_id'] as int;
      final remoteChildren = await _api.listChildren(token);
      final selected = await _store.readSelectedChild(userId);
      _token = token;
      _setAccount(account);
      _setChildren(remoteChildren, selected);
      await _loadPreferences();
      await refreshActiveClinicalData();
      await _store.writeToken(remember ? token : null);
    } catch (_) {
      _clearCachedIdentity();
      rethrow;
    }
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
      await _loadPreferences();
      await refreshActiveClinicalData();
      return true;
    } on ApiException catch (e) {
      _clearCachedIdentity();
      if (e.statusCode == 401) {
        await _store.writeToken(null); // expired or revoked token
      }
      return false;
    } catch (_) {
      // Network unavailable or secure storage error; do not expose cached data.
      _clearCachedIdentity();
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
    await refreshActiveClinicalData();
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
    screeningsByChild.remove(id);
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
    await refreshActiveClinicalData();
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
    _clearCachedIdentity();
  }

  Future<void> _loadPreferences() async {
    final prefs = await _api.preferences(_requiredToken);
    pushNotifications = prefs['push_notifications'] as bool;
    emailNotifications = prefs['email_notifications'] as bool;
    notifyListeners();
  }

  Future<void> updateGuardian({required String name, required String phone}) async {
    final user = await _api.updateGuardian(_requiredToken, name.trim(), phone.trim());
    _setAccount(user);
    notifyListeners();
  }

  Future<void> setNotificationPrefs({bool? push, bool? emailPref}) async {
    final prefs = await _api.savePreferences(_requiredToken,
        push: push ?? pushNotifications, email: emailPref ?? emailNotifications);
    pushNotifications = prefs['push_notifications'] as bool;
    emailNotifications = prefs['email_notifications'] as bool;
    notifyListeners();
  }

  final Map<String, List<MedicalRecord>> recordsByChild = {};
  final Map<String, List<ScreeningSummary>> screeningsByChild = {};
  final Map<String, Appointment> appointmentByChild = {};

  List<MedicalRecord> get activeRecords =>
      activeChildId == null ? [] : (recordsByChild[activeChildId] ?? []);

  List<ScreeningSummary> get activeScreenings =>
      activeChildId == null ? [] : (screeningsByChild[activeChildId] ?? []);

  Appointment? get activeAppointment =>
      activeChildId == null ? null : appointmentByChild[activeChildId];

  Future<void> refreshActiveClinicalData() async {
    final selected = activeChildId;
    if (selected == null) return;
    final token = _requiredToken;
    final rows = await Future.wait([
      _api.medicalRecords(token, selected),
      _api.appointments(token, selected),
      _api.screenings(token, selected),
    ]);
    // Ignore an earlier request if the user changed profiles during the fetch.
    if (activeChildId != selected || !isSignedIn) return;
    recordsByChild[selected] = rows[0].map((row) => MedicalRecord(
      id: row['record_id'] as int,
      fileName: row['file_name'] as String,
      type: row['record_type'] == 'imaging' ? RecordType.imaging : RecordType.document,
      date: row['created_at'] as String,
    )).toList();
    appointmentByChild.remove(selected);
    final plans = rows[1].where((row) => row['status'] != 'cancelled').toList();
    plans.sort((a, b) => DateTime.parse(a['scheduled_at'] as String)
        .compareTo(DateTime.parse(b['scheduled_at'] as String)));
    final now = DateTime.now();
    Map<String, dynamic>? nextPlan;
    for (final row in plans) {
      if (!DateTime.parse(row['scheduled_at'] as String).isBefore(now)) {
        nextPlan = row;
        break;
      }
    }
    nextPlan ??= plans.isNotEmpty ? plans.last : null;
    if (nextPlan != null) {
      final location = (nextPlan['location'] as String?) ?? '';
      CareCenter? match;
      for (final c in centers) {
        if (c.name == location) { match = c; break; }
      }
      appointmentByChild[selected] = Appointment(
        id: nextPlan['appointment_id'] as int,
        center: match ?? CareCenter(name: location, address: 'Contact provider to confirm', city: ''),
        scheduledAt: DateTime.parse(nextPlan['scheduled_at'] as String).toLocal(),
        status: nextPlan['status'] as String,
      );
    }
    screeningsByChild[selected] = rows[2].map((row) => ScreeningSummary(
      id: row['screening_id'] as int,
      modelName: row['model_name'] as String,
      predictedClass: row['predicted_class'] as String,
      date: row['screening_date'] as String,
      reviewAction: row['review_action'] as String?,
      reviewerName: row['reviewer_name'] as String?,
      reviewedAt: row['reviewed_at'] as String?,
    )).toList();
    notifyListeners();
  }

  Future<void> uploadMedicalRecord({required String fileName,
      required Uint8List bytes, required RecordType type}) async {
    final selected = activeChildId;
    if (selected == null) throw const ApiException('Select a child first.');
    await _api.uploadMedicalRecord(_requiredToken, selected,
      filename: fileName, bytes: bytes,
      recordType: type == RecordType.imaging ? 'imaging' : 'document');
    await refreshActiveClinicalData();
  }

  Future<Uint8List> downloadMedicalRecord(MedicalRecord record) async {
    final selected = activeChildId;
    if (selected == null) throw const ApiException('Select a child first.');
    return _api.downloadMedicalRecord(_requiredToken, selected, record.id);
  }

  Future<void> removeRecord(MedicalRecord record) async {
    final selected = activeChildId;
    if (selected == null) return;
    await _api.deleteMedicalRecord(_requiredToken, selected, record.id);
    await refreshActiveClinicalData();
  }

  Future<void> requestAppointment(CareCenter center, DateTime scheduled) async {
    final selected = activeChildId;
    if (selected == null) throw const ApiException('Select a child first.');
    await _api.addAppointment(_requiredToken, selected,
        scheduled: scheduled, location: center.name);
    await refreshActiveClinicalData();
  }

  Future<void> rescheduleAppointment(DateTime scheduled) async {
    final selected = activeChildId;
    final appointment = activeAppointment;
    if (selected == null || appointment == null) return;
    await _api.rescheduleAppointment(_requiredToken, selected, appointment.id, scheduled);
    await refreshActiveClinicalData();
  }

  Future<void> cancelAppointment() async {
    final selected = activeChildId;
    final appointment = activeAppointment;
    if (selected == null || appointment == null) return;
    await _api.cancelAppointment(_requiredToken, selected, appointment.id);
    await refreshActiveClinicalData();
  }

  Future<Map<String, dynamic>> submitScreening({required String modality,
      required String filename, required Uint8List bytes}) async {
    final selected = activeChildId;
    if (selected == null) throw const ApiException('Select a child before screening.');
    final response = await _api.predict(_requiredToken, selected,
        modality: modality, filename: filename, bytes: bytes);
    try {
      await refreshActiveClinicalData();
    } catch (_) {
      // Inference succeeded and the result is saved. A failed history reload
      // must not encourage submitting the same image twice.
    }
    return response;
  }

  // ---- updates from the clinic ------------------------------------------------

  final List<AppNotification> notifications = [];
  int get unreadNotifications => notifications.where((n) => !n.isRead).length;

  /// Called with each update that arrives while the app is open, if the
  /// guardian left push notifications on (the main screen shows a banner).
  void Function(AppNotification notification)? onNotification;

  Timer? _notificationTimer;
  bool _loadedNotifications = false;

  /// Checks for updates now and then every [every] while signed in. Started
  /// by the main screen, so it only runs while the app is in use.
  void startNotificationPolling({Duration every = const Duration(seconds: 15)}) {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(every, (_) => refreshNotifications().catchError((_) {}));
    unawaited(refreshNotifications().catchError((_) {}));
  }

  void stopNotificationPolling() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _loadedNotifications = false;
  }

  Future<void> refreshNotifications() async {
    final token = _token;
    if (token == null) return;
    final rows = await _api.notifications(token);
    if (_token != token) return; // signed out meanwhile
    final known = notifications.map((n) => n.id).toSet();
    final fresh = rows.map((row) => AppNotification(
      id: row['notification_id'] as int,
      title: row['title'] as String,
      body: row['body'] as String,
      createdAt: row['created_at'] as String,
      isRead: row['is_read'] as bool,
    )).toList();
    final arrived = fresh.where((n) => !n.isRead && !known.contains(n.id)).toList();
    notifications
      ..clear()
      ..addAll(fresh);
    notifyListeners();
    // Updates that came in while the app was closed are in the list; only
    // the ones that arrive while it is open get a banner.
    if (_loadedNotifications && arrived.isNotEmpty) {
      if (pushNotifications) arrived.forEach(onNotification ?? (_) {});
      // A review or status change also changes what the screens show.
      try {
        await refreshActiveClinicalData();
      } catch (_) {
        // The next check retries.
      }
    }
    _loadedNotifications = true;
  }

  Future<void> markNotificationsRead() async {
    if (unreadNotifications == 0) return;
    await _api.markNotificationsRead(_requiredToken);
    await refreshNotifications();
  }

  // ---- password reset (signed out) ----------------------------------------

  Future<void> requestPasswordReset(String email) => _api.forgotPassword(email.trim());

  Future<void> resetPassword({required String email, required String code,
      required String newPassword}) =>
      _api.resetPassword(email: email.trim(), code: code.trim(), newPassword: newPassword);

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
