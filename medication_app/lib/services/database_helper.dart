import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('medication.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dosage TEXT NOT NULL,
        duration_days INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE timings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        med_id INTEGER NOT NULL,
        time_str TEXT NOT NULL,
        FOREIGN KEY (med_id) REFERENCES medications (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE doses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        med_id INTEGER NOT NULL,
        scheduled_time TEXT NOT NULL,
        taken_time TEXT,
        status TEXT NOT NULL,
        trust_impact REAL DEFAULT 0.0,
        FOREIGN KEY (med_id) REFERENCES medications (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE stats (
        trust_score REAL DEFAULT 70.0,
        streak INTEGER DEFAULT 0,
        last_taken_date TEXT
      )
    ''');

    // Initial stats
    await db.insert('stats', {
      'trust_score': 70.0,
      'streak': 0,
    });
  }

  Future<int> insertMedication(Map<String, dynamic> med, List<String> timings) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      int medId = await txn.insert('medications', med);
      for (String t in timings) {
        await txn.insert('timings', {'med_id': medId, 'time_str': t});
      }
      return medId;
    });
  }

  Future<List<Map<String, dynamic>>> getMedications({String status = 'active'}) async {
    final db = await instance.database;
    return await db.query('medications', where: 'status = ?', whereArgs: [status]);
  }

  Future<List<String>> getTimings(int medId) async {
    final db = await instance.database;
    final res = await db.query('timings', where: 'med_id = ?', whereArgs: [medId]);
    return res.map((m) => m['time_str'] as String).toList();
  }

  Future<int> insertDose(Map<String, dynamic> dose) async {
    final db = await instance.database;
    return await db.insert('doses', dose);
  }

  Future<List<Map<String, dynamic>>> getDosesForRange(DateTime start, DateTime end) async {
    final db = await instance.database;
    return await db.query(
      'doses',
      where: 'scheduled_time BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'scheduled_time ASC',
    );
  }

  Future<int> updateDose(int id, Map<String, dynamic> values) async {
    final db = await instance.database;
    return await db.update('doses', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> getStats() async {
    final db = await instance.database;
    final res = await db.query('stats');
    return res.first;
  }

  Future<int> updateStats(Map<String, dynamic> values) async {
    final db = await instance.database;
    return await db.update('stats', values);
  }
  
  Future<void> clearAllMedications() async {
    final db = await instance.database;
    await db.delete('medications');
    await db.delete('timings');
    await db.delete('doses');
  }

  Future<void> deleteMedication(int id) async {
    final db = await instance.database;
    await db.delete('medications', where: 'id = ?', whereArgs: [id]);
    await db.delete('timings', where: 'med_id = ?', whereArgs: [id]);
    await db.delete('doses', where: 'med_id = ?', whereArgs: [id]);
  }
}
