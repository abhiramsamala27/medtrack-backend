import 'package:intl/intl.dart';

class Medication {
  final int? id;
  final String name;
  final String dosage;
  final int durationDays;
  final DateTime startDate;
  final String status; // 'active', 'completed'
  final List<String> timings; // ["09:00", "21:00"]

  Medication({
    this.id,
    required this.name,
    required this.dosage,
    required this.durationDays,
    required this.startDate,
    this.status = 'active',
    required this.timings,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'duration_days': durationDays,
      'start_date': DateFormat('yyyy-MM-dd').format(startDate),
      'status': status,
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map, List<String> timings) {
    return Medication(
      id: map['id'],
      name: map['name'],
      dosage: map['dosage'],
      durationDays: map['duration_days'],
      startDate: DateTime.parse(map['start_date']),
      status: map['status'],
      timings: timings,
    );
  }
}
