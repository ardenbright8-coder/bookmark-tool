// ---
// 这是啥: 协议编解码测试——业务 JSON 往返、垃圾输入防御
// 谁看: 改 models.dart 的人
// ---
import 'package:flutter_test/flutter_test.dart';
import 'package:bookmark_inbox/core/models.dart';

void main() {
  test('encodePayload 往返：字段齐全', () {
    final e = LedgerEntry(
      type: MsgType.bookmark,
      content: 'https://example.com',
      assignee: 'Claude',
      ts: 1700000000000,
      dedupeKey: 'abc-123',
    );
    final payload = LedgerEntry.tryDecodePayload(e.encodePayload());
    expect(payload, isNotNull);
    expect(payload!['type'], 'bookmark');
    expect(payload['content'], 'https://example.com');
    expect(payload['assignee'], 'Claude');
    expect(payload['dedupeKey'], 'abc-123');
    expect(payload['v'], 1);
  });

  test('tryDecodePayload：垃圾输入返回 null 不抛', () {
    expect(LedgerEntry.tryDecodePayload('不是json'), isNull);
    expect(LedgerEntry.tryDecodePayload('{"no":"key"}'), isNull);
    expect(LedgerEntry.tryDecodePayload('[1,2,3]'), isNull);
    expect(LedgerEntry.tryDecodePayload('{"dedupeKey":""}'), isNull);
  });

  test('未知 type 落回 note，cmd 是合法类型', () {
    expect(msgTypeFrom('cmd'), MsgType.cmd);
    expect(msgTypeFrom('不认识'), MsgType.note);
  });

  test('statusFrom 越界回 pending', () {
    expect(statusFrom(0), SendStatus.pending);
    expect(statusFrom(2), SendStatus.confirmed);
    expect(statusFrom(99), SendStatus.pending);
  });
}
