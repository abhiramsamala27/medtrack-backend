import 'package:intl/intl.dart';

class Dose {
  final int? id;
  final int medId;
  final String medName;
  final String dosage;
  final DateTime scheduledTime;
  DateTime? takenTime;
  String status; // 'PENDING', 'TAKEN', 'MISSED'
  double trustImpact;

  Dose({
    this.id,
    required this.medId,
    required this.medName,
    required this.dosage,
    required this.scheduledTime,
    this.takenTime,
    this.status = 'PENDING',
    this.trustImpact = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'med_id': medId,
      'scheduled_time': scheduledTime.toIso8601String(),
      'taken_time': takenTime?.toIso8601String(),
      'status': status,
      'trust_impact': trustImpact,
    };
  }

  factory Dose.fromMap(Map<String, dynamic> map, String medName, String dosage) {
    return Dose(
      id: map['id'],
      medId: map['med_id'],
      medName: medName,
      dosage: dosage,
      scheduledTime: DateTime.parse(map['scheduled_time']),
      takenTime: map['taken_time'] != null ? DateTime.parse(map['taken_time']) : null,
      status: map['status'],
      trustImpact: map['trust_impact'],
    );
  }
}
