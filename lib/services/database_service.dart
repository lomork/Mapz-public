import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

import '../models/discovered_road.dart';
import '../models/trip_history_model.dart';


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
      version: 5,
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
        longitude REAL NOT NULL,
        country TEXT DEFAULT 'Unknown'
      )
    ''');
    await _createTripHistoryTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE discovered_roads ADD COLUMN country TEXT DEFAULT 'Unknown'");
        print("Database upgraded: 'country' column added.");
      } catch (e) {
        // If the column already exists, this might throw, which is fine.
        print("Migration error (safe to ignore if column exists): $e");
      }
    }
    if (oldVersion < 5) {
      await _createTripHistoryTable(db);
    }
  }

  Future<void> _createTripHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE trip_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startAddress TEXT,
        endAddress TEXT,
        startTime INTEGER, -- Store as millisecondsSinceEpoch
        endTime INTEGER,
        durationSeconds INTEGER,
        distanceText TEXT,
        routePathJson TEXT -- Store List<LatLng> as JSON string
      )
    ''');
  }

  Future<void> insertRoads(List<DiscoveredRoad> roads) async {
    Database db = await database;
    Batch batch = db.batch();

    for (var road in roads) {
      batch.insert(
        'discovered_roads',
        road.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<DiscoveredRoad>> getAllDiscoveredRoads() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('discovered_roads');

    return List.generate(maps.length, (i) {
      return DiscoveredRoad.fromMap(maps[i]);
    });
  }

  Future<int> getRoadsCount({String? country}) async {
    Database db = await database;

    if (country != null) {
      final result = await db.rawQuery(
          'SELECT COUNT(*) FROM discovered_roads WHERE country = ?',
          [country]
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } else {
      final result = await db.rawQuery('SELECT COUNT(*) FROM discovered_roads');
      return Sqflite.firstIntValue(result) ?? 0;
    }
  }

  Future<int> insertTrip(TripHistory trip) async {
    Database db = await database;
    return await db.insert('trip_history', trip.toMap());
  }

  Future<List<TripHistory>> getAllTrips() async {
    Database db = await database;
    // Order by newest first
    final List<Map<String, dynamic>> maps = await db.query('trip_history', orderBy: "startTime DESC");
    return List.generate(maps.length, (i) => TripHistory.fromMap(maps[i]));
  }

  Future<int> deleteTrip(int id) async {
    Database db = await database;
    return await db.delete('trip_history', where: 'id = ?', whereArgs: [id]);
  }
}