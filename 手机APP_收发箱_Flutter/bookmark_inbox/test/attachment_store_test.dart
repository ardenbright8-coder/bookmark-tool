// ---
// 这是啥: 本地贴图仓库测试——拷贝/防撞名/路径穿越/删除
// 谁看: 改 attachment_store.dart 的人
// ---
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:bookmark_inbox/core/attachment_store.dart';
import 'package:bookmark_inbox/core/models.dart';

void main() {
  late Directory tmp;
  late AttachmentStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('att_store');
    store = AttachmentStore(rootDir: tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('importFile 拷进 attachments 子目录，返回纯文件名', () async {
    final src = File(p.join(tmp.path, 'from_gallery.jpg'));
    await src.writeAsBytes(const [1, 2, 3, 4]);
    final name = await store.importFile(src.path);
    expect(name.contains('/'), false);
    expect(name.contains('\\'), false);
    expect(name.endsWith('.jpg'), true);
    expect(RegExp(r'^\d+_[0-9a-f]{6}\.jpg$').hasMatch(name), true);
    final copied = store.fileOf(name);
    expect(copied.path, p.join(tmp.path, 'attachments', name));
    expect(await copied.readAsBytes(), const [1, 2, 3, 4]);
  });

  test('两次 import 文件名不撞', () async {
    final src = File(p.join(tmp.path, 'shot.png'));
    await src.writeAsBytes(const [9]);
    final a = await store.importFile(src.path);
    final b = await store.importFile(src.path);
    expect(a, isNot(b));
    expect(await store.fileOf(a).exists(), true);
    expect(await store.fileOf(b).exists(), true);
  });

  test('fileOf 剥掉路径穿越，文件仍落在 attachments 内', () {
    final f = store.fileOf('..${p.separator}secret.jpg');
    expect(p.normalize(f.path), p.normalize(p.join(store.directory.path, 'secret.jpg')));
    expect(p.isWithin(p.normalize(store.directory.path), p.normalize(f.path)), true);
  });

  test('deleteNamed 缺文件不抛，在的删掉', () async {
    final src = File(p.join(tmp.path, 'x.webp'));
    await src.writeAsBytes(const [7]);
    final name = await store.importFile(src.path);
    await store.deleteNamed([name, 'nope.jpg', '../x']);
    expect(await store.fileOf(name).exists(), false);
  });

  test('attachmentFileName 只留文件名', () {
    expect(attachmentFileName(r'C:\tmp\a.jpg'), 'a.jpg');
    expect(attachmentFileName('/data/a/b.png'), 'b.png');
    expect(attachmentFileName('..'), '');
    expect(attachmentFileName(''), '');
  });
}
