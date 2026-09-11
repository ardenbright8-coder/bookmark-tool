// ---
// 这是啥: 本地贴图仓库——相册/拍照文件拷进 APP 私有 attachments 子目录，条目只记文件名
// 谁看: 界面选图、列表/详情读图、删条目时清文件
// 什么时候用: 选图入库、展示缩略图、删除附件
// 改之前必看: 本期图只留手机本地，不上传邮局；返回值永远是纯文件名；core 禁沾 widget
// ---
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'models.dart';

const _okExt = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp'};

class AttachmentStore {
  AttachmentStore({required this.rootDir});

  /// APP 私有目录（与账本 db 同级），其下 `attachments/` 存图
  final String rootDir;

  Directory get directory => Directory(p.join(rootDir, 'attachments'));

  Future<void> ensureReady() async {
    await directory.create(recursive: true);
  }

  /// 拷贝源文件进 attachments/，返回纯文件名（时间戳+随机数防撞）。
  Future<String> importFile(String sourcePath) async {
    await ensureReady();
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw ArgumentError('源文件不存在');
    }
    final ext = p.extension(sourcePath).toLowerCase();
    final useExt = _okExt.contains(ext) ? ext : '.jpg';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final name = '${stamp}_$rand$useExt';
    await src.copy(p.join(directory.path, name));
    return name;
  }

  File fileOf(String name) {
    final safe = attachmentFileName(name);
    if (safe.isEmpty) {
      throw ArgumentError('非法附件名');
    }
    return File(p.join(directory.path, safe));
  }

  Future<void> deleteNamed(Iterable<String> names) async {
    for (final n in names) {
      final safe = attachmentFileName(n);
      if (safe.isEmpty) continue;
      final f = File(p.join(directory.path, safe));
      if (await f.exists()) await f.delete();
    }
  }
}
