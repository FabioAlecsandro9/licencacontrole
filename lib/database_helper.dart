import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'licencas.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE licencas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome_evento TEXT NOT NULL,
        data_inicial TEXT NOT NULL,
        data_final TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE
      )
    ''');
  }

  Future<int> insertLicenca(Map<String, dynamic> licenca) async {
    final db = await database;
    return await db.insert('licencas', licenca);
  }

  Future<List<Map<String, dynamic>>> queryAllLicencas() async {
    final db = await database;
    return await db.query('licencas');
  }

  Future<int> deleteLicenca(int id) async {
    final db = await database;
    return await db.delete('licencas', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> tokenExists(String token) async {
    final db = await database;
    final result = await db.query(
      'licencas',
      where: 'token = ?',
      whereArgs: [token],
    );
    return result.isNotEmpty;
  }
}
