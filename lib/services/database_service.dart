// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/discovered_road.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'mapz.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Create the table based on your DiscoveredRoad model
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE discovered_roads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        placeId TEXT UNIQUE NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add the new column to the existing table
      await db.execute("ALTER TABLE discovered_roads ADD COLUMN country TEXT DEFAULT 'Unknown'");
    }
  }

  // --- CRUD Operations ---

  // Batch Insert (for _snapAndStorePath)
  Future<void> insertRoads(List<DiscoveredRoad> roads) async {
    Database db = await database;
    Batch batch = db.batch();

    for (var road in roads) {
      // Use `conflictAlgorithm: ConflictAlgorithm.ignore` so it simply
      // skips any roads that have a `placeId` that already exists.
      batch.insert(
        'discovered_roads',
        road.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  // Read All (for getAllDiscoveredPoints)
  Future<List<DiscoveredRoad>> getAllDiscoveredRoads() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('discovered_roads');

    return List.generate(maps.length, (i) {
      return DiscoveredRoad.fromMap(maps[i]);
    });
  }

  // Count (for calculateDiscoveryPercentage)
  Future<int> getRoadsCount({String? country}) async {
    Database db = await database;

    if (country != null) {
      // Return count ONLY for the specific country
      final result = await db.rawQuery(
          'SELECT COUNT(*) FROM discovered_roads WHERE country = ?',
          [country]
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } else {
      // Fallback to total count (or global stats)
      final result = await db.rawQuery('SELECT COUNT(*) FROM discovered_roads');
      return Sqflite.firstIntValue(result) ?? 0;
    }
  }
}