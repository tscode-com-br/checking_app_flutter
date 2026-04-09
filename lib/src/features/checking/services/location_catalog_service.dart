import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class LocationCatalogService {
  static const _databaseName = 'checking_locations.db';
  static const _tableName = 'locations';

  Future<Database>? _databaseFuture;

  Future<List<ManagedLocation>> loadLocations() async {
    final database = await _openDatabase();
    final rows = await database.query(
      _tableName,
      orderBy: 'local COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(ManagedLocation.fromDatabase).toList(growable: false);
  }

  Future<void> replaceLocations(List<ManagedLocation> items) async {
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
  }

  Future<Database> _openDatabase() {
    _databaseFuture ??= _initDatabase();
    return _databaseFuture!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final filePath = path.join(databasePath, _databaseName);
    return openDatabase(
      filePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY,
            local TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            tolerance_meters INTEGER NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
  }
}
