// ---
// 这是啥: 发送状态机测试——MockClient 模拟邮局成功/失败，验证落库→发送→回退全链
// 谁看: 改 sender.dart 的人
// 改之前必看: 只测逻辑，不连真邮局
// ---
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookmark_inbox/core/config.dart';
import 'package:bookmark_inbox/core/ledger.dart';
import 'package:bookmark_inbox/core/models.dart';
import 'package:bookmark_inbox/core/ntfy_client.dart';
import 'package:bookmark_inbox/core/sender.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LedgerStore store;
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('sender_test');
    store = LedgerStore(factory: databaseFactory);
    await store.open(tmp.path);
  });
  tearDown(() async => store.close());

  Sender makeSender(http.Client client) => Sender(
        store: store,
        client: NtfyClient(client: client),
        configLoader: () async => ChannelConfig(
          server: 'https://mail.test',
          user: 'u', pass: 'p',
          upTopic: 'bookmark-up', receiptTopic: 'bookmark-receipt',
        ),
      );

  test('发送成功：状态转 sent，请求里带认证头和业务 JSON', () async {
    Uri? captured;
    final client = MockClient((req) async {
      captured = req.url;
      expect(req.headers['Authorization'], startsWith('Basic '));
      return http.Response('{"id":"srv1"}', 200);
    });
    final id = await makeSender(client)
        .composeAndSend(type: MsgType.task, content: '改电脑时间', assignee: 'Grok');
    expect((await store.byId(id))!.status, SendStatus.sent);
    expect(captured!.toString(), 'https://mail.test/bookmark-up');
  });

  test('发送失败：回到 pending、attempts+1、lastError 记录', () async {
    final client = MockClient((req) async => http.Response('denied', 403));
    final id = await makeSender(client).composeAndSend(content: 'x');
    final e = (await store.byId(id))!;
    expect(e.status, SendStatus.pending);
    expect(e.attempts, 1);
    expect(e.lastError, contains('403'));
  });

  test('邮局未配置：留在 pending 并给可读提示，不抛', () async {
    final sender = Sender(
      store: store,
      client: NtfyClient(client: MockClient((req) async => http.Response('', 200))),
      configLoader: () async => ChannelConfig(
        server: '', user: '', pass: '',
        upTopic: 'bookmark-up', receiptTopic: 'bookmark-receipt',
      ),
    );
    final id = await sender.composeAndSend(content: 'y');
    final e = (await store.byId(id))!;
    expect(e.status, SendStatus.pending);
    expect(e.lastError, contains('未配置'));
  });

  test('发送 JSON 带 attachments 文件名，不带路径、不带图字节', () async {
    String? message;
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      message = body['message'] as String;
      return http.Response('{"id":"srv1"}', 200);
    });
    await makeSender(client).composeAndSend(
      content: '看图',
      attachments: ['shot.jpg', r'/sdcard/DCIM/nope.png'],
    );
    final payload = jsonDecode(message!) as Map<String, dynamic>;
    expect(payload['content'], '看图');
    expect(payload['attachments'], ['shot.jpg', 'nope.png']);
    expect(message!.contains('/sdcard'), false);
    expect(message!.contains('base64'), false);
    expect(message!.length, lessThan(500));
  });

  test('retryPending：待发的逐条尝试，成功转 sent', () async {
    var fail = true;
    final client = MockClient((req) async {
      if (fail) return http.Response('offline', 500);
      return http.Response('{"id":"ok"}', 200);
    });
    final sender = makeSender(client);
    final id = await sender.composeAndSend(content: '断网时存的'); // 发送失败→留在待发
    expect((await store.byId(id))!.status, SendStatus.pending);
    fail = false; // 网络恢复
    final n = await sender.retryPending();
    expect(n, 1);
    expect((await store.byId(id))!.status, SendStatus.sent);
  });
}
