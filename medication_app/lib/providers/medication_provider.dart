import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/medication.dart';
import '../models/dose.dart';
import '../services/database_helper.dart';

class MedicationProvider with ChangeNotifier {
  List<Medication> _meds = [];
  List<Dose> _todayDoses = [];
  double _trustScore = 70.0;
  int _streak = 0;

  List<Medication> get meds => _meds;
  List<Dose> get todayDoses => _todayDoses;
  double get trustScore => _trustScore;
  int get streak => _streak;

  MedicationProvider() {
    init();
  }

  Future<void> init() async {
    await loadStats();
    await loadMedications();
    await generateDailyDoses();
  }

  Future<void> loadStats() async {
    final stats = await DatabaseHelper.instance.getStats();
    _trustScore = stats['trust_score'] ?? 70.0;
    _streak = stats['streak'] ?? 0;
    notifyListeners();
  }

  Future<void> loadMedications() async {
    final res = await DatabaseHelper.instance.getMedications();
    List<Medication> loaded = [];
    for (var m in res) {
      final timings = await DatabaseHelper.instance.getTimings(m['id']);
      loaded.add(Medication.fromMap(m, timings));
    }
    _meds = loaded;
    notifyListeners();
  }

  Future<void> generateDailyDoses() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // 1. Get existing doses for today
    final existingRaw = await DatabaseHelper.instance.getDosesForRange(startOfDay, endOfDay);
    
    // 2. Map meds name/dosage for display
    final Map<int, Medication> medMap = {for (var m in _meds) m.id!: m};

    // 3. For each active med, check if doses exist for today
    for (var med in _meds) {
      if (med.status != 'active') continue;

      for (var tStr in med.timings) {
        final timeParts = tStr.split(':');
        final schedTime = DateTime(now.year, now.month, now.day, int.parse(timeParts[0]), int.parse(timeParts[1]));

        bool exists = existingRaw.any((d) => 
          DateTime.parse(d['scheduled_time']).hour == schedTime.hour &&
          DateTime.parse(d['scheduled_time']).minute == schedTime.minute &&
          d['med_id'] == med.id
        );

        if (!exists) {
          await DatabaseHelper.instance.insertDose({
             'med_id': med.id,
             'scheduled_time': schedTime.toIso8601String(),
             'status': 'PENDING',
             'trust_impact': 0.0,
          });
        }
      }
    }

    // 4. Reload doses for current display
    final updatedRaw = await DatabaseHelper.instance.getDosesForRange(startOfDay, endOfDay);
    _todayDoses = updatedRaw.map((d) {
      final med = medMap[d['med_id']];
      return Dose.fromMap(d, med?.name ?? 'Unknown', med?.dosage ?? '---');
    }).toList();

    // 5. Auto-mark missed if > 2 hours late
    for (var dose in _todayDoses) {
      if (dose.status == 'PENDING' && now.isAfter(dose.scheduledTime.add(const Duration(hours: 2)))) {
        await markDoseMissed(dose.id!);
      }
    }

    notifyListeners();
  }

  Future<void> addMedication(String name, String dosage, int duration, List<String> timings) async {
    final med = Medication(
      name: name,
      dosage: dosage,
      durationDays: duration,
      startDate: DateTime.now(),
      timings: timings,
    );
    await DatabaseHelper.instance.insertMedication(med.toMap(), timings);
    await loadMedications();
    await generateDailyDoses();
  }

  Future<void> markDoseTaken(int id) async {
    final dose = _todayDoses.firstWhere((d) => d.id == id);
    if (dose.status != 'PENDING') return;

    final now = DateTime.now();
    await DatabaseHelper.instance.updateDose(id, {
      'status': 'TAKEN',
      'taken_time': now.toIso8601String(),
      'trust_impact': 2.0,
    });

    // Update Stats
    double newTrust = (_trustScore + 2.0).clamp(0.0, 100.0);
    int newStreak = _streak + 1; // Simplification: increment on every SUCCESS dose for now
    
    await DatabaseHelper.instance.updateStats({
      'trust_score': newTrust,
      'streak': newStreak,
      'last_taken_date': DateFormat('yyyy-MM-dd').format(now),
    });

    _trustScore = newTrust;
    _streak = newStreak;

    await generateDailyDoses();
  }

  Future<void> markDoseMissed(int id) async {
    final dose = _todayDoses.firstWhere((d) => d.id == id);
    if (dose.status != 'PENDING') return;

    await DatabaseHelper.instance.updateDose(id, {
      'status': 'MISSED',
      'trust_impact': -1.0,
    });

    // Update Stats
    double newTrust = (_trustScore - 1.0).clamp(0.0, 100.0);
    int newStreak = 0;
    
    await DatabaseHelper.instance.updateStats({
      'trust_score': newTrust,
      'streak': newStreak,
    });

    _trustScore = newTrust;
    _streak = newStreak;

    await generateDailyDoses();
  }
}
