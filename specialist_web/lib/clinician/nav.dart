import 'package:flutter/foundation.dart';

enum Section { overview, queue, patients, schedule, screening, system, settings, security }

extension SectionX on Section {
  String get label {
    switch (this) {
      case Section.overview:
        return 'Overview';
      case Section.queue:
        return 'Screenings';
      case Section.patients:
        return 'Patients';
      case Section.schedule:
        return 'Schedule';
      case Section.screening:
        return 'Run a screening';
      case Section.system:
        return 'Models & system';
      case Section.settings:
        return 'Settings';
      case Section.security:
        return 'Security';
    }
  }
}

/// Which page the portal shows. Opening a patient keeps the Patients section
/// selected and shows that patient's record.
class Nav extends ChangeNotifier {
  Nav._();
  static final Nav instance = Nav._();

  Section section = Section.overview;
  String? patientId;

  /// Patient to preselect on the "Run a screening" page.
  String? screeningPatientId;

  void go(Section s) {
    section = s;
    patientId = null;
    notifyListeners();
  }

  void openPatient(String id) {
    section = Section.patients;
    patientId = id;
    notifyListeners();
  }

  void screenPatient(String id) {
    section = Section.screening;
    screeningPatientId = id;
    patientId = null;
    notifyListeners();
  }

  void reset() {
    section = Section.overview;
    patientId = null;
    screeningPatientId = null;
  }
}
