// ---
// 这是啥: 条目贴图 UI——缩略图条、点开大图、相册/拍照入库
// 谁看: 看板创建窗、条目详情
// 什么时候用: 选图、列表/详情展示
// 改之前必看: 只调 AttachmentStore，不把路径写进条目；core 禁 import 本文件
// ---
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/attachment_store.dart';

Future<List<String>> pickAndImportImages({
  required AttachmentStore store,
  required ImageSource source,
}) async {
  final picker = ImagePicker();
  final paths = <String>[];
  if (source == ImageSource.gallery) {
    final files = await picker.pickMultiImage();
    paths.addAll(files.map((f) => f.path));
  } else {
    final f = await picker.pickImage(source: source);
    if (f != null) paths.add(f.path);
  }
  final names = <String>[];
  for (final path in paths) {
    names.add(await store.importFile(path));
  }
  return names;
}

void showFullAttachment(
  BuildContext context, {
  required AttachmentStore store,
  required String name,
}) {
  final file = store.fileOf(name);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(name, style: const TextStyle(fontSize: 14)),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(
              file,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 缩略图条。点图看大图；[onRemove] 非空时显示删除角标。
class AttachmentThumbStrip extends StatelessWidget {
  const AttachmentThumbStrip({
    super.key,
    required this.store,
    required this.names,
    this.size = 44,
    this.onRemove,
  });

  final AttachmentStore store;
  final List<String> names;
  final double size;
  final void Function(String name)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names) _thumb(context, name),
      ],
    );
  }

  Widget _thumb(BuildContext context, String name) {
    Widget img;
    try {
      final file = store.fileOf(name);
      img = Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).toInt(),
        errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: size * 0.6),
      );
    } catch (_) {
      img = Icon(Icons.broken_image, size: size * 0.6);
    }
    final tile = GestureDetector(
      onTap: () => showFullAttachment(context, store: store, name: name),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: size, height: size, child: img),
      ),
    );
    if (onRemove == null) return tile;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, bottom: 0, child: tile),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              iconSize: 18,
              tooltip: '去掉这张',
              onPressed: () => onRemove!(name),
              icon: const Icon(Icons.cancel, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
