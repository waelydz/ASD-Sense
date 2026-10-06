class Child {
  final String id;
  String name;
  String age;

  Child({required this.id, required this.name, required this.age});
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

class CareCenter {
  final String name;
  final String address;
  final String city;

  CareCenter({required this.name, required this.address, required this.city});
}

class Appointment {
  final CareCenter center;

  Appointment({required this.center});
}
