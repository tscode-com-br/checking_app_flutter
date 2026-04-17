import 'dart:convert';

import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocationCatalogService {
  static const _databaseName = 'checking_locations.db';
  static const _tableName = 'locations';
  static const _prefsCacheKey = 'checking_locations_catalog_cache_v1';

  LocationCatalogService({
    Future<Database> Function()? databaseOpener,
    Future<SharedPreferences> Function()? sharedPreferencesLoader,
  }) : _databaseOpener = databaseOpener,
       _sharedPreferencesLoader = sharedPreferencesLoader;

  Future<Database>? _databaseFuture;
  final Future<Database> Function()? _databaseOpener;
  final Future<SharedPreferences> Function()? _sharedPreferencesLoader;

  Future<List<ManagedLocation>> loadLocations({
    bool preferCache = false,
  }) async {
    final cachedLocations = preferCache
        ? await _readLocationsFromPrefs()
        : null;
    if (preferCache && cachedLocations != null && cachedLocations.isNotEmpty) {
      return cachedLocations;
    }

    try {
      final database = await _openDatabase();
      final rows = await database.query(
        _tableName,
        orderBy: 'local COLLATE NOCASE ASC, id ASC',
      );
      final locations = rows
          .map(ManagedLocation.fromDatabase)
          .toList(growable: false);
      await _cacheLocationsInPrefs(locations);
      return locations;
    } catch (_) {
      return cachedLocations ?? await _readLocationsFromPrefs() ?? const [];
    }
  }

  Future<void> replaceLocations(List<ManagedLocation> items) async {
    final cachedSuccessfully = await _cacheLocationsInPrefs(items);

    try {
      final database = await _openDatabase();
      await database.transaction((transaction) async {
        await transaction.delete(_tableName);
        final batch = transaction.batch();
        for (final item in items) {
          batch.insert(
            _tableName,
            item.toDatabase(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {
      if (!cachedSuccessfully) {
        rethrow;
      }
    }
  }

  Future<Database> _openDatabase() {
    _databaseFuture ??= _databaseOpener?.call() ?? _initDatabase();
    return _databaseFuture!;
  }

  Future<SharedPreferences> _loadSharedPreferences() {
    final sharedPreferencesLoader = _sharedPreferencesLoader;
    if (sharedPreferencesLoader != null) {
      return sharedPreferencesLoader();
    }
    return SharedPreferences.getInstance();
  }

  Future<List<ManagedLocation>?> _readLocationsFromPrefs() async {
    try {
      final prefs = await _loadSharedPreferences();
      final raw = prefs.getString(_prefsCacheKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }

      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                ManagedLocation.fromDatabase(Map<String, Object?>.from(row)),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _cacheLocationsInPrefs(List<ManagedLocation> items) async {
    try {
      final prefs = await _loadSharedPreferences();
      final encoded = jsonEncode(
        items.map((item) => item.toDatabase()).toList(growable: false),
      );
      return prefs.setString(_prefsCacheKey, encoded);
    } catch (_) {
      return false;
    }
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final filePath = path.join(databasePath, _databaseName);
    return openDatabase(
      filePath,
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY,
            local TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            coordinates_json TEXT,
            tolerance_meters INTEGER NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE $_tableName ADD COLUMN coordinates_json TEXT',
          );
        }
      },
    );
  }
}
