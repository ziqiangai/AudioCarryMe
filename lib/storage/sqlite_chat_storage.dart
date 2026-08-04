import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/conversation.dart';
import '../models/generation_task.dart';
import '../models/log_entry.dart';
import '../models/message.dart';
import '../models/model_catalog.dart';
import '../models/request_log.dart';
import 'chat_storage.dart';

/// SQLite 实现：两张表
///   conversations(id, name, created_at)
///   messages(id, conversation_id, text, sender, time)
class SqliteChatStorage implements ChatStorage {
  SqliteChatStorage._(this._db);
  final Database _db;

  /// 打开（或首次创建）数据库。
  static Future<SqliteChatStorage> open() async {
    final path = p.join(await getDatabasesPath(), 'carry_me.db');
    final db = await openDatabase(
      path,
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations(
            id         TEXT PRIMARY KEY,
            name       TEXT    NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE messages(
            id              TEXT PRIMARY KEY,
            conversation_id TEXT    NOT NULL,
            text            TEXT    NOT NULL,
            sender          INTEGER NOT NULL,
            time            INTEGER NOT NULL,
            quoted_author   TEXT,
            quoted_text     TEXT,
            task_id         TEXT,
            is_prompt_card  INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          )''');
        await db.execute(
          'CREATE INDEX idx_messages_conv_time ON messages(conversation_id, time)',
        );
        await _createRequestLogsTable(db);
        await _createLogsTable(db);
        await _createGenerationTasksTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2：为消息表加引用字段。
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN quoted_author TEXT');
          await db.execute('ALTER TABLE messages ADD COLUMN quoted_text TEXT');
        }
        // v2 → v3：请求记录表。
        if (oldVersion < 3) {
          await _createRequestLogsTable(db);
        }
        // v3 → v4：运行日志表。
        if (oldVersion < 4) {
          await _createLogsTable(db);
        }
        // v4 → v5：生成任务表 + 消息关联列。
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE messages ADD COLUMN task_id TEXT');
          await _createGenerationTasksTable(db);
        }
        // v5 → v6：提示词卡片标记。
        if (oldVersion < 6) {
          await db.execute(
              'ALTER TABLE messages ADD COLUMN is_prompt_card INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
    return SqliteChatStorage._(db);
  }

  @override
  Future<List<Conversation>> loadConversations() async {
    final convRows = await _db.query('conversations');
    final conversations = <Conversation>[];
    for (final row in convRows) {
      final conv = Conversation(
        id: row['id'] as String,
        name: row['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );
      final msgRows = await _db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conv.id],
        orderBy: 'time ASC',
      );
      for (final m in msgRows) {
        conv.messages.add(Message(
          id: m['id'] as String,
          text: m['text'] as String,
          sender: Sender.values[m['sender'] as int],
          time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
          quotedAuthor: m['quoted_author'] as String?,
          quotedText: m['quoted_text'] as String?,
          taskId: m['task_id'] as String?,
          isPromptCard: (m['is_prompt_card'] as int? ?? 0) == 1,
        ));
      }
      conversations.add(conv);
    }
    return conversations;
  }

  @override
  Future<void> upsertConversation(Conversation conversation) async {
    await _db.insert(
      'conversations',
      {
        'id': conversation.id,
        'name': conversation.name,
        'created_at': conversation.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> insertMessage(String conversationId, Message message) async {
    await _db.insert(
      'messages',
      {
        'id': message.id,
        'conversation_id': conversationId,
        'text': message.text,
        'sender': message.sender.index,
        'time': message.time.millisecondsSinceEpoch,
        'quoted_author': message.quotedAuthor,
        'quoted_text': message.quotedText,
        'task_id': message.taskId,
        'is_prompt_card': message.isPromptCard ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    await _db.delete('conversations', where: 'id = ?', whereArgs: [conversationId]);
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  static Future<void> _createRequestLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE request_logs(
        id                    TEXT PRIMARY KEY,
        started_at            INTEGER NOT NULL,
        input_tokens          INTEGER NOT NULL,
        cache_read_tokens     INTEGER NOT NULL,
        cache_creation_tokens INTEGER NOT NULL,
        output_tokens         INTEGER NOT NULL,
        response_latency_ms   INTEGER NOT NULL,
        total_duration_ms     INTEGER NOT NULL,
        ok                    INTEGER NOT NULL,
        error                 TEXT
      )''');
    await db.execute(
      'CREATE INDEX idx_request_logs_time ON request_logs(started_at DESC)',
    );
  }

  @override
  Future<List<RequestLog>> loadRequestLogs() async {
    final rows = await _db.query('request_logs', orderBy: 'started_at DESC');
    return rows
        .map((r) => RequestLog(
              id: r['id'] as String,
              startedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
              inputTokens: r['input_tokens'] as int,
              cacheReadTokens: r['cache_read_tokens'] as int,
              cacheCreationTokens: r['cache_creation_tokens'] as int,
              outputTokens: r['output_tokens'] as int,
              responseLatency:
                  Duration(milliseconds: r['response_latency_ms'] as int),
              totalDuration:
                  Duration(milliseconds: r['total_duration_ms'] as int),
              ok: (r['ok'] as int) == 1,
              error: r['error'] as String?,
            ))
        .toList();
  }

  @override
  Future<void> insertRequestLog(RequestLog log) async {
    await _db.insert('request_logs', {
      'id': log.id,
      'started_at': log.startedAt.millisecondsSinceEpoch,
      'input_tokens': log.inputTokens,
      'cache_read_tokens': log.cacheReadTokens,
      'cache_creation_tokens': log.cacheCreationTokens,
      'output_tokens': log.outputTokens,
      'response_latency_ms': log.responseLatency.inMilliseconds,
      'total_duration_ms': log.totalDuration.inMilliseconds,
      'ok': log.ok ? 1 : 0,
      'error': log.error,
    });
  }

  static Future<void> _createLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE logs(
        id      TEXT PRIMARY KEY,
        time    INTEGER NOT NULL,
        level   INTEGER NOT NULL,
        tag     TEXT    NOT NULL,
        message TEXT    NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_logs_time ON logs(time DESC)');
  }

  @override
  Future<List<LogEntry>> loadLogs() async {
    final rows = await _db.query('logs', orderBy: 'time DESC', limit: 2000);
    return rows
        .map((r) => LogEntry(
              id: r['id'] as String,
              time: DateTime.fromMillisecondsSinceEpoch(r['time'] as int),
              level: LogLevel.values[r['level'] as int],
              tag: r['tag'] as String,
              message: r['message'] as String,
            ))
        .toList();
  }

  @override
  Future<void> insertLog(LogEntry entry) async {
    await _db.insert('logs', {
      'id': entry.id,
      'time': entry.time.millisecondsSinceEpoch,
      'level': entry.level.index,
      'tag': entry.tag,
      'message': entry.message,
    });
  }

  @override
  Future<void> clearLogs() async {
    await _db.delete('logs');
  }

  static Future<void> _createGenerationTasksTable(Database db) async {
    await db.execute('''
      CREATE TABLE generation_tasks(
        id              TEXT PRIMARY KEY,
        conversation_id TEXT    NOT NULL,
        kind            INTEGER NOT NULL,
        model_id        TEXT    NOT NULL,
        prompt          TEXT    NOT NULL,
        params          TEXT    NOT NULL,
        status          INTEGER NOT NULL,
        ppio_task_id    TEXT,
        result_urls     TEXT    NOT NULL,
        error           TEXT,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX idx_gen_tasks_status ON generation_tasks(status)',
    );
  }

  @override
  Future<List<GenerationTask>> loadGenerationTasks() async {
    final rows = await _db.query('generation_tasks', orderBy: 'created_at ASC');
    return rows
        .map((r) => GenerationTask(
              id: r['id'] as String,
              conversationId: r['conversation_id'] as String,
              kind: GenKind.values[r['kind'] as int],
              modelId: r['model_id'] as String,
              prompt: r['prompt'] as String,
              params: GenerationTask.decodeParams(r['params'] as String),
              status: GenTaskStatus.values[r['status'] as int],
              ppioTaskId: r['ppio_task_id'] as String?,
              resultUrls: GenerationTask.decodeUrls(r['result_urls'] as String),
              error: r['error'] as String?,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              updatedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
            ))
        .toList();
  }

  @override
  Future<void> upsertGenerationTask(GenerationTask task) async {
    await _db.insert(
      'generation_tasks',
      {
        'id': task.id,
        'conversation_id': task.conversationId,
        'kind': task.kind.index,
        'model_id': task.modelId,
        'prompt': task.prompt,
        'params': task.paramsJson,
        'status': task.status.index,
        'ppio_task_id': task.ppioTaskId,
        'result_urls': task.resultUrlsJson,
        'error': task.error,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
