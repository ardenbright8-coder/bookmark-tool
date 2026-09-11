// ---
// 这是啥: 本地账本（sqflite）——每条记录先落这里再发送，永不丢
// 谁看: sender（落库/改状态）、界面账本页（列表）、receipt_sync（回执确认）
// 什么时候用: 一切对账本的读写
// 改之前必看: dedupeKey 唯一，重复插入会被静默忽略；status 语义见 SendStatus；
//   v2 加 attachments TEXT（JSON 数组，只存文件名），旧库 onUpgrade 补列，别把 version 撤回 1
// ---
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

const _createSql = '''
        CREATE TABLE entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          content TEXT NOT NULL,
          assignee TEXT NOT NULL DEFAULT '',
          ts INTEGER NOT NULL,
          dedupeKey TEXT NOT NULL UNIQUE,
          status INTEGER NOT NULL DEFAULT 0,
          attempts INTEGER NOT NULL DEFAULT 0,
          lastError TEXT NOT NULL DEFAULT '',
          attachments TEXT NOT NULL DEFAULT '[]'
        )
      ''';

class LedgerStore {
  LedgerStore({this.factory});

  final DatabaseFactory? factory;
  Database? _db;

  Database get db => _db!;

  Future<void> open(String dir) async {
    _db = await (factory ?? databaseFactory).openDatabase(
      '$dir/bookmark_inbox.db',
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, v) => d.execute(_createSql),
        onUpgrade: (d, old, neu) async {
          if (old < 2) {
            await d.execute(
              "ALTER TABLE entries ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'",
            );
          }
        },
      ),
    );
  }

  Future<bool> get isOpen async => _db != null;

  Future<void> close() async => _db?.close();

  /// 插入待发记录；dedupeKey 撞车（已存在）返回已存在的 id，不重复插。
  Future<int> insertPending(LedgerEntry e) async {
    final id = await db.insert('entries', e.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) return id;
    final hit = await db.query('entries',
        where: 'dedupeKey = ?', whereArgs: [e.dedupeKey], limit: 1);
    return (hit.single['id'] as int);
  }

  /// 最新在前（账本页）
  Future<List<LedgerEntry>> entries({int limit = 200}) async {
    final rows = await db
        .query('entries', orderBy: 'ts DESC, id DESC', limit: limit);
    return rows.map(LedgerEntry.fromRow).toList();
  }

  Future<List<LedgerEntry>> pendingEntries() async {
    final rows = await db.query('entries',
        where: 'status = ?', whereArgs: [SendStatus.pending.index],
        orderBy: 'ts ASC, id ASC');
    return rows.map(LedgerEntry.fromRow).toList();
  }

  Future<LedgerEntry?> byId(int id) async {
    final rows = await db.query('entries',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerEntry.fromRow(rows.single);
  }

  Future<void> markSent(int id) async {
    await db.update('entries', {'status': SendStatus.sent.index, 'lastError': ''},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id, String error) async {
    await db.rawUpdate(
      'UPDATE entries SET status = ?, attempts = attempts + 1, lastError = ? WHERE id = ?',
      [SendStatus.pending.index, error, id],
    );
  }

  /// 回执确认：按 dedupeKey 命中即置 confirmed，天然幂等。返回命中条数。
  Future<int> markConfirmed(String dedupeKey) async {
    return db.update('entries', {'status': SendStatus.confirmed.index},
        where: 'dedupeKey = ?', whereArgs: [dedupeKey]);
  }

  Future<void> deleteEntry(int id) async =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);

  /// 回执通知用：按 dedupeKey 找还没确认的记录（已确认的不重复弹）。
  Future<List<LedgerEntry>> unconfirmedByKey(String dedupeKey) async {
    final rows = await db.query('entries',
        where: 'dedupeKey = ? AND status != ?',
        whereArgs: [dedupeKey, SendStatus.confirmed.index]);
    return rows.map(LedgerEntry.fromRow).toList();
  }

  /// 看板移动分组：只改归属（assignee），不动内容与 dedupeKey。
  Future<void> updateAssignee(int id, String assignee) async {
    await db.update('entries', {'assignee': assignee},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 改本地附件文件名列表（本期图不重新上传邮局）。
  Future<void> updateAttachments(int id, List<String> names) async {
    await db.update(
      'entries',
      {'attachments': jsonEncode(attachmentNamesFrom(names))},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
