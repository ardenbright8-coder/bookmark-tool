// ---
// 这是啥: APP 入口——初始化账本/通知，唯一 home=Agent 看板，启动时补发待发项+补拉回执
// 谁看: Flutter 框架
// 什么时候用: 每次 APP 启动
// 改之前必看: 初始化失败（比如库打不开）要给用户可见报错，别白屏；
//   初始化是异步的，首帧必须等 _ready，否则 late final 全局一读就炸
// ---
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ledger.dart';
import 'core/notifier.dart';
import 'core/ntfy_client.dart';
import 'core/receipt_sync.dart';
import 'core/sender.dart';
import 'core/config.dart';
import 'ui/agent_board_page.dart';

late final LedgerStore gStore;
late final Sender gSender;
late final ReceiptSync gReceiptSync;
final Notifier gNotifier = Notifier();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookmarkInboxApp());
}

class BookmarkInboxApp extends StatelessWidget {
  const BookmarkInboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '书签收发箱',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8FA578),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _revision = 0;
  bool _ready = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      gStore = LedgerStore();
      final dir = await getApplicationDocumentsDirectory();
      await gStore.open(dir.path);
      gSender = Sender(store: gStore, client: NtfyClient(), configLoader: _loadCfg);
      gReceiptSync = ReceiptSync(store: gStore, client: gSender.client);
      await gNotifier.init();
      // 启动即补账：待发的重发一遍、回执补拉一轮；失败静默（看板上可见状态）
      unawaited(gSender.retryPending().whenComplete(() => _bump()));
      unawaited(gReceiptSync
          .sync(await _loadCfg(),
              onNewlyConfirmed: (contents) => gNotifier.show(
                  '电脑已收录 ${contents.length} 条',
                  contents.take(3).join('、')))
          .whenComplete(() => _bump()));
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _fatal = e.toString());
    }
  }

  Future<ChannelConfig> _loadCfg() => ChannelConfig.load();

  void _bump() {
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    if (_fatal != null) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('启动失败：$_fatal', textAlign: TextAlign.center),
        )),
      );
    }
    // 初始化是异步的：没就绪先给加载页，否则 late final 全局在首帧就被读，必炸
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AgentBoardPage(
      store: gStore,
      sender: gSender,
      receiptSync: gReceiptSync,
      revision: _revision,
      onChanged: _bump,
    );
  }
}
