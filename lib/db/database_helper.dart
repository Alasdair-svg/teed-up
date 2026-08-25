/// SQLite database helper for the All Teed Up golf booking app.
///
/// Manages a single database with three tables:
/// - **contact_cache** — maps player names to resolved email addresses.
/// - **rsvp_cache** — caches the last-known RSVP status per event+email.
/// - **alerts** — records RSVP status changes for the alerts feed.
///
/// Uses the singleton pattern so only one connection exists app-wide.
library;

import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Current database schema version.
///
/// Bump this when adding migrations in [_onUpgrade].
const int _kDatabaseVersion = 1;

/// Database file name on disk.
const String _kDatabaseName = 'teed_up.db';

/// Singleton helper for all local SQLite operations.
///
/// ```dart
/// final db = DatabaseHelper.instance;
/// await db.insertContactCache({...});
/// ```
class DatabaseHelper {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  DatabaseHelper._internal();

  /// The single, shared [DatabaseHelper] instance.
  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// The underlying [Database] handle, lazily initialised.
  Database? _database;

  /// Returns the open database, creating it on first access.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<Database> _initDatabase() async {
    // On iOS, Application Support is excluded from iCloud backup by the OS.
    // On Android, getApplicationDocumentsDirectory() maps to internal storage
    // which is already sandboxed and not cloud-synced.
    final dir = Platform.isIOS
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _kDatabaseName);

    return openDatabase(
      dbPath,
      version: _kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Enable foreign keys for referential integrity.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Creates all tables on a fresh install.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contact_cache (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        email       TEXT    NOT NULL,
        source      TEXT    NOT NULL DEFAULT 'auto',
        is_manual   INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
    ''');

    // Index for fast look-ups by normalised name.
    await db.execute('''
      CREATE INDEX idx_contact_cache_name
        ON contact_cache (name COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE TABLE rsvp_cache (
        event_id    TEXT NOT NULL,
        email       TEXT NOT NULL,
        status      TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        PRIMARY KEY (event_id, email)
      )
    ''');

    await db.execute('''
      CREATE TABLE alerts (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id      TEXT    NOT NULL,
        player_name   TEXT    NOT NULL,
        player_email  TEXT,
        old_status    TEXT    NOT NULL,
        new_status    TEXT    NOT NULL,
        detected_at   TEXT    NOT NULL,
        is_read       INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Index for filtering unread alerts quickly.
    await db.execute('''
      CREATE INDEX idx_alerts_unread
        ON alerts (is_read) WHERE is_read = 0
    ''');
  }

  /// Handles schema migrations between versions.
  ///
  /// Each migration block should run only for the appropriate version jump.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Example skeleton for future migrations:
    // if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  // ---------------------------------------------------------------------------
  // contact_cache CRUD
  // ---------------------------------------------------------------------------

  /// Inserts a new contact cache entry.
  ///
  /// Returns the inserted row ID.
  Future<int> insertContactCache(Map<String, dynamic> row) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    row['created_at'] ??= now;
    row['updated_at'] ??= now;
    return db.insert('contact_cache', row);
  }

  /// Returns all contact cache rows.
  Future<List<Map<String, dynamic>>> queryAllContactCache() async {
    final db = await database;
    return db.query('contact_cache', orderBy: 'name COLLATE NOCASE ASC');
  }

  /// Looks up contact cache entries by [name] (case-insensitive).
  ///
  /// Results are ordered so manual corrections appear first.
  Future<List<Map<String, dynamic>>> queryContactCacheByName(
    String name,
  ) async {
    final db = await database;
    return db.query(
      'contact_cache',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      orderBy: 'is_manual DESC, updated_at DESC',
    );
  }

  /// Checks whether a manual correction exists for [name].
  Future<bool> hasManualCorrection(String name) async {
    final db = await database;
    final rows = await db.query(
      'contact_cache',
      where: 'name = ? COLLATE NOCASE AND is_manual = 1',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Updates an existing contact cache entry by [id].
  ///
  /// Returns the number of rows affected.
  Future<int> updateContactCache(int id, Map<String, dynamic> row) async {
    final db = await database;
    row['updated_at'] = DateTime.now().toIso8601String();
    return db.update(
      'contact_cache',
      row,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a contact cache entry by [id].
  Future<int> deleteContactCache(int id) async {
    final db = await database;
    return db.delete('contact_cache', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes all *auto-resolved* (non-manual) entries for [name].
  ///
  /// This is called before inserting a fresh auto-resolution to avoid
  /// stale duplicates while preserving manual corrections.
  Future<int> deleteAutoEntriesForName(String name) async {
    final db = await database;
    return db.delete(
      'contact_cache',
      where: 'name = ? COLLATE NOCASE AND is_manual = 0',
      whereArgs: [name],
    );
  }

  /// Removes all non-manual cache entries (preserves manual corrections).
  Future<int> clearAutoCache() async {
    final db = await database;
    return db.delete('contact_cache', where: 'is_manual = 0');
  }

  // ---------------------------------------------------------------------------
  // rsvp_cache CRUD
  // ---------------------------------------------------------------------------

  /// Upserts an RSVP cache entry (insert-or-replace on composite PK).
  Future<int> upsertRsvpCache(Map<String, dynamic> row) async {
    final db = await database;
    row['updated_at'] ??= DateTime.now().toIso8601String();
    return db.insert(
      'rsvp_cache',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the cached RSVP status for [eventId] and [email], or `null`.
  Future<String?> getRsvpStatus(String eventId, String email) async {
    final db = await database;
    final rows = await db.query(
      'rsvp_cache',
      columns: ['status'],
      where: 'event_id = ? AND email = ?',
      whereArgs: [eventId, email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['status'] as String?;
  }

  /// Returns all RSVP cache entries for a given [eventId].
  Future<List<Map<String, dynamic>>> queryRsvpCacheByEvent(
    String eventId,
  ) async {
    final db = await database;
    return db.query(
      'rsvp_cache',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  /// Deletes all RSVP cache entries for [eventId].
  Future<int> deleteRsvpCacheByEvent(String eventId) async {
    final db = await database;
    return db.delete(
      'rsvp_cache',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  // ---------------------------------------------------------------------------
  // alerts CRUD
  // ---------------------------------------------------------------------------

  /// Inserts a new alert row and returns its ID.
  Future<int> insertAlert(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('alerts', row);
  }

  /// Returns all alerts, newest first.
  Future<List<Map<String, dynamic>>> queryAllAlerts() async {
    final db = await database;
    return db.query('alerts', orderBy: 'detected_at DESC');
  }

  /// Returns only unread alerts, newest first.
  Future<List<Map<String, dynamic>>> queryUnreadAlerts() async {
    final db = await database;
    return db.query(
      'alerts',
      where: 'is_read = 0',
      orderBy: 'detected_at DESC',
    );
  }

  /// Returns alerts for a specific [eventId].
  Future<List<Map<String, dynamic>>> queryAlertsByEvent(String eventId) async {
    final db = await database;
    return db.query(
      'alerts',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'detected_at DESC',
    );
  }

  /// Marks a single alert as read.
  Future<int> markAlertRead(int id) async {
    final db = await database;
    return db.update(
      'alerts',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks all alerts as read.
  Future<int> markAllAlertsRead() async {
    final db = await database;
    return db.update(
      'alerts',
      {'is_read': 1},
      where: 'is_read = 0',
    );
  }

  /// Deletes a single alert by [id].
  Future<int> deleteAlert(int id) async {
    final db = await database;
    return db.delete('alerts', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes all alerts for a given [eventId].
  Future<int> deleteAlertsByEvent(String eventId) async {
    final db = await database;
    return db.delete('alerts', where: 'event_id = ?', whereArgs: [eventId]);
  }

  /// Returns the count of unread alerts.
  Future<int> countUnreadAlerts() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM alerts WHERE is_read = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the database connection.
  ///
  /// After calling this, the next access to [database] will re-open it.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }
}
