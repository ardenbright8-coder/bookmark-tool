// ---
// 这是啥: Agent 看板主页——照电脑看板的样子：三个页签「💭 待定 / 🤖 Agent 分组 / 📁 项目」，每组第一格是空白框，条目 01 02 编号
// 谁看: main 的唯一 home
// 什么时候用: 打开 APP 即看板
// 改之前必看: 看板以电脑为准（设定19）：打开、下拉、每 30 秒拉一份电脑发到中转站的整板（board_sync.dart），
//   手机只把「自己发了、看板上还没有的」单列出来标「等电脑收」；挪组 / 删条 / 早上审完「可以，删掉」
//   都是发命令给电脑（sender.sendOp），电脑照做后下一份整板就变了，手机先照着改好（乐观更新）。
//   🚨 2026-09-25 用户拍板：跟电脑一样分三个页签（点页签或左右滑换页，记住上次停在哪页），推翻 09-10 的「单页不许改」；
//   项目页只能看（夹和 md 内容跟整板一起来），不能建不能改。不放数数的小标、组框不折叠（设定13）；
//   分组名单以电脑为准，手机不加组（加组去电脑看板）。
// ---
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/attachment_store.dart';
import '../core/board_sync.dart';
import '../core/config.dart';
import '../core/ledger.dart';
import '../core/models.dart';
import '../core/receipt_sync.dart';
import '../core/sender.dart';
import 'agents_roster.dart';
import 'attachment_views.dart';
import 'settings_dialog.dart';

// 草木皮肤（跟电脑看板同一套颜色）
const _ink = Color(0xFF2F3E2C);
const _leaf = Color(0xFF7A9C5E);
const _leafDark = Color(0xFF4D6B3A);
const _muted = Color(0x8C2F3E2C);

class AgentBoardPage extends StatefulWidget {
  const AgentBoardPage({
    super.key,
    required this.store,
    required this.sender,
    required this.receiptSync,
    required this.attachments,
    required this.revision,
    required this.onChanged,
  });

  final LedgerStore store;
  final Sender sender;
  final ReceiptSync receiptSync;
  final AttachmentStore attachments;
  final int revision; // main 侧数据版本号，变了就重拉
  final VoidCallback onChanged;

  @override
  State<AgentBoardPage> createState() => _AgentBoardPageState();
}

/// 看板上一组：key 是组名（待定 = ''，交接单专区 = _handoffKey）
class _Group {
  _Group(this.key, this.name, this.items, this.mine);
  final String key;
  final String name;
  final List<BoardItem> items;
  final List<LedgerEntry> mine; // 自己发的、看板上还没有的
}

const _handoffKey = '__handoff__';

class _AgentBoardPageState extends State<AgentBoardPage> with SingleTickerProviderStateMixin {
  static const _kTab = 'board.tab';
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: 1);
  String _projPath = ''; // 项目页当前在哪个夹（根＝''）
  List<LedgerEntry> _entries = [];
  List<String> _fallbackAgents = [];
  BoardSnapshot? _snap;
  bool _syncing = false;
  int _lastRevision = -1;
  Timer? _poll;
  late final BoardSync _boardSync = BoardSync(client: widget.sender.client);
  // 发了命令、电脑还没抄新的一份：先照着改好（乐观更新），新整板到了就清掉
  final Set<String> _hidden = {};
  Set<String> _seen = {};
  final Map<String, String> _moved = {};

  @override
  void initState() {
    super.initState();
    _reload();
    unawaited(_refreshAll());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_pullBoard()));
    // 记住上次停在哪页，下次打开还在那页
    unawaited(SharedPreferences.getInstance().then((p) {
      final i = p.getInt(_kTab);
      if (mounted && i != null && i >= 0 && i < 3) _tabs.index = i;
    }));
    _tabs.addListener(() {
      _dropFocus();
      if (_tabs.indexIsChanging) return;
      final i = _tabs.index;
      if (mounted) setState(() {}); // 返回键管不管项目页，跟着当前页签变
      unawaited(SharedPreferences.getInstance().then((p) => p.setInt(_kTab, i)));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgentBoardPage old) {
    super.didUpdateWidget(old);
    if (widget.revision != _lastRevision) _reload();
  }

  Future<void> _reload() async {
    _lastRevision = widget.revision;
    final entries = await widget.store.entries();
    final agents = await AgentRoster().load();
    if (mounted) {
      setState(() {
        _entries = entries;
        _fallbackAgents = agents;
      });
    }
  }

  Future<void> _pullBoard() async {
    final snap = await _boardSync.fetch(await ChannelConfig.load());
    final seen = await BoardSync.seenKeys();
    if (!mounted || snap == null) return;
    setState(() {
      _seen = seen;
      if (_snap == null || snap.ts != _snap!.ts) {
        _hidden.clear();
        _moved.clear();
      }
      _snap = snap;
    });
  }

  /// 弹菜单、刷新之前先把光标从空白框里拿出来：菜单一关 Flutter 会把光标还回去，键盘就自己弹出来了
  void _dropFocus() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _refreshAll() async {
    _dropFocus();
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final cfg = await ChannelConfig.load();
      await widget.sender.retryPending();
      await widget.receiptSync.sync(cfg);
      await _pullBoard();
      await _reload();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<String> get _agents => _snap?.agents.isNotEmpty == true ? _snap!.agents : _fallbackAgents;

  String _assigneeOf(BoardItem i) => _moved[i.id] ?? i.assignee ?? '';

  /// 分组（单页）：💭待定置顶 → 名单顺序 → 名单外的老组 → 最底下交接单专区
  List<_Group> _groups() {
    final items = (_snap?.items ?? const <BoardItem>[]).where((i) => !_hidden.contains(i.id)).toList();
    final mine = notOnBoardYet(_entries, _snap, seen: _seen);
    bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();
    final groups = <_Group>[
      _Group('', '待定（想想区）', items.where((i) => _assigneeOf(i).isEmpty && !i.isHandoff).toList(),
          mine.where((e) => e.assignee.isEmpty).toList()),
      for (final a in _agents)
        _Group(a, a, items.where((i) => same(_assigneeOf(i), a)).toList(),
            mine.where((e) => same(e.assignee, a)).toList()),
    ];
    final known = _agents.map((a) => a.toLowerCase()).toSet();
    final extras = {
      ...items.map(_assigneeOf),
      ...mine.map((e) => e.assignee),
    }.where((a) => a.isNotEmpty && !known.contains(a.toLowerCase()));
    for (final a in extras) {
      groups.add(_Group(a, a, items.where((i) => _assigneeOf(i) == a).toList(),
          mine.where((e) => e.assignee == a).toList()));
    }
    groups.add(_Group(_handoffKey, '交接单（AI 干完活留下的）',
        items.where((i) => _assigneeOf(i).isEmpty && i.isHandoff).toList(), const []));
    return groups;
  }

  // ── 记一条 / 挪 / 删 ──

  Future<void> _write(String assignee, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await widget.sender.composeAndSend(type: MsgType.task, content: t, assignee: assignee);
    widget.onChanged();
    await _reload();
  }

  Future<void> _writeWithImage(String assignee) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickTaskDialog(assignee: assignee, sender: widget.sender, attachments: widget.attachments),
    );
    if (ok != true) return;
    widget.onChanged();
    await _reload();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Future<void> _sendOp(BoardItem item, {required String op, String assignee = ''}) async {
    _dropFocus();
    final ok = await widget.sender.sendOp(op: op, id: item.id, assignee: assignee);
    if (!mounted) return;
    if (!ok) {
      _toast('没发出去（网不通？），电脑那边没动，等会儿再试');
      return;
    }
    setState(() => op == 'delete' ? _hidden.add(item.id) : _moved[item.id] = assignee);
    _toast(op == 'delete' ? '已让电脑删掉这条' : '已让电脑挪到 ${assignee.isEmpty ? '待定' : assignee}');
  }

  Future<void> _itemMenu(BoardItem item) async {
    _dropFocus();
    final here = _assigneeOf(item);
    final targets = ['', ..._agents].where((a) => a.toLowerCase() != here.toLowerCase()).toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('挪到……', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final a in targets)
              ListTile(
                dense: true,
                leading: _GroupLogo(name: a, size: 20),
                title: Text(a.isEmpty ? '待定' : a),
                onTap: () => Navigator.of(ctx).pop('to:$a'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删掉这条', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'delete') {
      await _sendOp(item, op: 'delete');
    } else {
      await _sendOp(item, op: 'assign', assignee: choice.substring(3));
    }
  }

  Future<void> _mineMenu(LedgerEntry e) async {
    _dropFocus();
    final del = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('这条电脑还没收到', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('从手机上删掉（没发出去的就不发了）', style: TextStyle(color: Colors.redAccent)),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ]),
      ),
    );
    if (del != true) return;
    await widget.attachments.deleteNamed(e.attachments);
    await widget.store.deleteEntry(e.id!);
    widget.onChanged();
    await _reload();
  }

  Future<void> _openItem(BoardItem item) async {
    _dropFocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (item.isHandoff) const Text('📋 交接单', style: TextStyle(color: _leafDark, fontWeight: FontWeight.w600)),
              SelectableText(displayText(item.text), style: const TextStyle(height: 1.4, fontSize: 15, color: _ink)),
              if (item.detail != null) ...[
                const SizedBox(height: 10),
                SelectableText(item.detail!, style: const TextStyle(height: 1.4, color: _ink)),
              ],
              if (item.url != null) ...[
                const SizedBox(height: 8),
                SelectableText(item.url!, style: const TextStyle(color: _leafDark)),
              ],
              if (item.images > 0) ...[
                const SizedBox(height: 8),
                Text('🖼 有 ${item.images} 张图在电脑上（图不上传中转站）', style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // ── 画面 ──

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    final pending = groups.first; // 待定永远排第一个
    final agentGroups = groups.sublist(1);
    Widget page(List<Widget> children) => _KeepAlive(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 28),
              children: [if (_snap == null) _noBoardHint(), ...children],
            ),
          ),
        );
    // 项目页点进了子夹：手机返回键＝回上一层，不退出应用（2026-09-25 模拟器上实测踩到）
    final inSubFolder = _tabs.index == 2 && _projPath.isNotEmpty;
    return PopScope(
      canPop: !inSubFolder,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !inSubFolder) return;
        final i = _projPath.lastIndexOf('/');
        setState(() => _projPath = i < 0 ? '' : _projPath.substring(0, i));
      },
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F8EE), Color(0xFFE2ECD5)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            _titleBar(),
            _tabBar(pending.items.length + pending.mine.length),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                page([_groupCard(pending)]),
                page([for (final g in agentGroups) _groupCard(g)]),
                page(_projectPage()),
              ]),
            ),
          ]),
        ),
      ),
      ),
    );
  }

  /// 三个页签，长相照电脑看板：圆角小胶囊，选中的那个是淡绿底；待定带条数（电脑上也带）
  Widget _tabBar(int pendingCount) {
    Widget tab(String icon, String label, {int? count}) => Tab(
          height: 34,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 5),
            Text(label),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: const TextStyle(fontSize: 11.5, color: _leafDark)),
              ),
            ],
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: TabBar(
        controller: _tabs,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(17),
        indicator: BoxDecoration(
          color: _leaf.withValues(alpha: 0.28),
          border: Border.all(color: _leaf.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(17),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelColor: _ink,
        unselectedLabelColor: _ink.withValues(alpha: 0.6),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: [
          tab('💭', '待定', count: pendingCount),
          tab('🤖', 'Agent 分组'),
          tab('📁', '项目'),
        ],
      ),
    );
  }

  // ── 项目页（只能看）：一层一层点进去，点 md 看内容 ──

  List<Widget> _projectPage() {
    final roots = _snap?.projects;
    if (_snap != null && roots == null) {
      return [_hint('电脑看板还是老版本，没把项目页发过来。电脑上按 Ctrl+R 换成新版就有了。')];
    }
    final all = roots ?? const <ProjectNode>[];
    var here = projectChildrenAt(all, _projPath);
    if (here == null) {
      // 当前这个夹电脑上已经没了：退回最上面
      _projPath = '';
      here = all;
    }
    final crumbs = _projPath.isEmpty ? <String>[] : _projPath.split('/');
    return [
      Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          border: Border.all(color: _leaf.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 路径：📁 项目 › 中医 › …，点哪一段回到哪一层
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              _crumb('📁 项目', ''),
              for (var i = 0; i < crumbs.length; i++) ...[
                const Text(' › ', style: TextStyle(color: _muted)),
                _crumb(crumbs[i], crumbs.sublist(0, i + 1).join('/')),
              ],
            ]),
          ),
          if (here.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Text(all.isEmpty ? '电脑上还没有项目夹。建夹、建文档去电脑看板的「📁 项目」页。' : '这个夹是空的。',
                  style: const TextStyle(fontSize: 12, color: _muted)),
            ),
          for (final n in here) _projectRow(n),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text('手机上只能看；建夹、写文档去电脑看板。', style: TextStyle(fontSize: 11, color: _muted)),
          ),
        ]),
      ),
    ];
  }

  Widget _crumb(String label, String path) {
    final current = path == _projPath;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: current ? null : () => setState(() => _projPath = path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(label,
            style: TextStyle(
                fontSize: 15, fontWeight: current ? FontWeight.w700 : FontWeight.w500, color: current ? _ink : _leafDark)),
      ),
    );
  }

  Widget _projectRow(ProjectNode n) => _rowShell(
        onTap: () => n.dir ? setState(() => _projPath = n.path) : _openDoc(n),
        child: Row(children: [
          Text(n.dir ? '📁' : '📄', style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(n.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14.5)),
          ),
          if (n.dir) const Icon(Icons.chevron_right, color: _muted, size: 20),
        ]),
      );

  Future<void> _openDoc(ProjectNode n) async {
    _dropFocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📄 ${n.name}', style: const TextStyle(color: _leafDark, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              SelectableText(
                n.content == null ? '（电脑那边没读到这份的内容）' : (n.content!.trim().isEmpty ? '（空文档）' : n.content!),
                style: const TextStyle(height: 1.5, fontSize: 14.5, color: _ink),
              ),
              if (n.truncated) ...[
                const SizedBox(height: 10),
                const Text('…… 太长了，手机上只带了前面一截，全文去电脑上看。', style: TextStyle(color: _muted, fontSize: 12)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text) => Container(
        margin: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 12, color: _ink, height: 1.4)),
      );

  Widget _titleBar() {
    final snap = _snap;
    String when = '还没拉到电脑的看板';
    if (snap != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(snap.ts);
      final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final today = DateTime.now();
      final sameDay = t.year == today.year && t.month == today.month && t.day == today.day;
      when = '电脑 ${sameDay ? '' : '${t.month}/${t.day} '}$hm 的看板';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
      child: Row(children: [
        const Text('🌿', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        const Text('Agent 看板', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_syncing ? '同步中…' : when,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _muted)),
        ),
        if (snap != null)
          Tooltip(
            message: '在电脑看板上切换',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: snap.sleep ? const Color(0xFF2F3B52) : Colors.white.withValues(alpha: 0.6),
                border: Border.all(color: snap.sleep ? const Color(0xFF2F3B52) : _leaf.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(snap.sleep ? '🌙 睡觉档' : '☀️ 日常档',
                  style: TextStyle(fontSize: 11, color: snap.sleep ? const Color(0xFFF1E7C4) : _leafDark)),
            ),
          ),
        IconButton(
          tooltip: '邮局设置',
          icon: const Icon(Icons.settings_outlined, color: _leafDark, size: 20),
          onPressed: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
        ),
      ]),
    );
  }

  Widget _noBoardHint() => Container(
        margin: const EdgeInsets.fromLTRB(2, 2, 2, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('还没拉到电脑那边的看板：电脑开着看板才会发过来。下面先只列手机自己发过的。往下拉可以再试一次。',
            style: TextStyle(fontSize: 12, color: _ink, height: 1.4)),
      );

  Widget _groupCard(_Group g) {
    final isHandoff = g.key == _handoffKey;
    var n = 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        border: Border.all(color: _leaf.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(children: [
            _GroupLogo(name: g.key == _handoffKey ? '📋' : g.key, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(g.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
            ),
          ]),
        ),
        if (!isHandoff) _BlankBox(onSubmit: (t) => _write(g.key, t), onImage: () => _writeWithImage(g.key)),
        for (final e in g.mine) _mineRow(e),
        for (final item in g.items) _itemRow(item, ++n),
        if (isHandoff && g.items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text('AI 干完活留下的交接单在这里。', style: TextStyle(fontSize: 12, color: _muted)),
          ),
      ]),
    );
  }

  Widget _rowShell({required Widget child, VoidCallback? onTap, VoidCallback? onLongPress}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: child),
          ),
        ),
      );

  Widget _itemRow(BoardItem item, int order) {
    return _rowShell(
      onTap: () => _openItem(item),
      onLongPress: () => _itemMenu(item),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 24,
          child: Text(order.toString().padLeft(2, '0'), style: const TextStyle(color: _muted, fontSize: 13, height: 1.5)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayText(item.text),
                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14.5, height: 1.4)),
            if (item.isHandoff || item.claimedBy != null || item.images > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  if (item.isHandoff) const _Chip('📋 交接单'),
                  if (item.claimedBy != null) _Chip('🔄 ${item.claimedBy} 在干'),
                  if (item.images > 0) _Chip('🖼 ${item.images}'),
                ]),
              ),
            if (item.report != null) _reportBlock(item),
          ]),
        ),
      ]),
    );
  }

  Widget _reportBlock(BoardItem item) {
    var when = '';
    final at = item.reportedAt == null ? null : DateTime.tryParse(item.reportedAt!)?.toLocal();
    if (at != null) when = ' · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: _leaf.withValues(alpha: 0.12),
        border: const Border(left: BorderSide(color: _leaf, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('✅ 干完待审 · ${item.reportedBy ?? ''}$when',
            style: const TextStyle(color: _leafDark, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 2),
        Text(item.report!, style: const TextStyle(color: _ink, fontSize: 13, height: 1.4)),
        const SizedBox(height: 4),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: _leafDark,
            side: BorderSide(color: _leaf.withValues(alpha: 0.6)),
          ),
          onPressed: () => _sendOp(item, op: 'delete'),
          child: const Text('可以，删掉'),
        ),
      ]),
    );
  }

  Widget _mineRow(LedgerEntry e) {
    final (color, label) = switch (e.status) {
      SendStatus.confirmed => (_leafDark, '📨 电脑已收，等下一份看板'),
      SendStatus.sent => (const Color(0xFF5E86A8), '⏳ 已送出，等电脑收'),
      SendStatus.pending => (const Color(0xFFB07A2E), '⏳ 还没发出去${e.attempts > 0 ? '（失败 ${e.attempts} 次，下拉重试）' : ''}'),
    };
    return _rowShell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _EntryDetailDialog(entry: e, store: widget.store, attachments: widget.attachments),
      ).then((_) => _reload()),
      onLongPress: () => _mineMenu(e),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(width: 24, child: Text('··', style: TextStyle(color: _muted, fontSize: 13, height: 1.5))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14.5, height: 1.4)),
            if (e.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AttachmentThumbStrip(store: widget.attachments, names: e.attachments, size: 36),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(label, style: TextStyle(color: color, fontSize: 11)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 每组第一格的常驻空白框（跟电脑设定17一样）：点进去就写，回车就发、框清空、光标留着接着写；右边小图标＝带图记一条
class _BlankBox extends StatefulWidget {
  const _BlankBox({required this.onSubmit, required this.onImage});
  final Future<void> Function(String text) onSubmit;
  final VoidCallback onImage;

  @override
  State<_BlankBox> createState() => _BlankBoxState();
}

class _BlankBoxState extends State<_BlankBox> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.replaceAll('\n', ' ');
    _ctrl.clear();
    _focus.requestFocus();
    if (text.trim().isEmpty) return;
    await widget.onSubmit(text);
  }

  /// 回车＝记下这条（跟电脑看板一样）：多行框里敲回车会塞进一个换行，见到换行就当回车
  void _onChanged(String value) {
    if (value.contains('\n')) unawaited(_submit());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _submit(),
        onChanged: _onChanged,
        style: const TextStyle(fontSize: 14.5, color: _ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: '写一条…',
          hintStyle: TextStyle(color: _ink.withValues(alpha: 0.35)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.35),
          contentPadding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _ink.withValues(alpha: 0.16)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _ink.withValues(alpha: 0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _leaf.withValues(alpha: 0.7)),
          ),
          suffixIcon: IconButton(
            tooltip: '带图记一条',
            icon: Icon(Icons.image_outlined, color: _leafDark.withValues(alpha: 0.55), size: 20),
            onPressed: widget.onImage,
          ),
        ),
      ),
    );
  }
}

/// 页签换走时别把页面拆了：空白框里写了一半的字、翻到的位置都留着
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: _leaf.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: _leafDark)),
      );
}

/// 组名前的标志：照电脑看板那五家的样子，认不出的组是叶形圆点
class _GroupLogo extends StatelessWidget {
  const _GroupLogo({required this.name, this.size = 22});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = name.toLowerCase();
    Widget glyph(String t, Color c, {double scale = 1}) =>
        Text(t, style: TextStyle(fontSize: size * scale, color: c, height: 1, fontWeight: FontWeight.w700));
    Widget child;
    if (name.isEmpty) {
      child = glyph('💭', _ink, scale: 0.85);
    } else if (name == '📋') {
      child = glyph('📋', _ink, scale: 0.85);
    } else if (n.contains('claude')) {
      child = Icon(Icons.flare, size: size, color: const Color(0xFFD97757)); // ✳ 在安卓上会变成绿色表情，改用图标
    } else if (n.contains('chatgpt') || n.contains('codex') || n.contains('openai')) {
      child = glyph('◎', _ink);
    } else if (n == 'pi' || n.startsWith('pi ')) {
      final s = size / 2.2;
      Widget sq(Color c) => Container(width: s, height: s, color: c);
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [sq(const Color(0xFFF09082)), sq(const Color(0xFFF09082))]),
        Row(mainAxisSize: MainAxisSize.min, children: [sq(const Color(0xFF4D9ABF)), sq(const Color(0xFFF1BE58))]),
      ]);
    } else if (n.contains('antigravity')) {
      child = ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
        ).createShader(r),
        child: glyph('Λ', Colors.white),
      );
    } else if (n.contains('hermes')) {
      child = glyph('⚕', const Color(0xFF3D5A2C));
    } else {
      child = Container(
        width: size * 0.55,
        height: size * 0.55,
        decoration: const BoxDecoration(color: _leaf, shape: BoxShape.circle),
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: child));
  }
}

/// 空白框右边小图标弹的带图记一条窗：类型三选（默认任务），发送走 Sender（先落账本）
class _QuickTaskDialog extends StatefulWidget {
  const _QuickTaskDialog({
    required this.assignee,
    required this.sender,
    required this.attachments,
  });

  final String assignee; // 空串=待定组
  final Sender sender;
  final AttachmentStore attachments;

  @override
  State<_QuickTaskDialog> createState() => _QuickTaskDialogState();
}

class _QuickTaskDialogState extends State<_QuickTaskDialog> {
  final _ctrl = TextEditingController();
  MsgType _type = MsgType.task;
  bool _sending = false;
  bool _committed = false;
  final List<String> _names = [];
  String? _pickError;

  @override
  void dispose() {
    _ctrl.dispose();
    if (!_committed && _names.isNotEmpty) {
      unawaited(widget.attachments.deleteNamed(List<String>.from(_names)));
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final added = await pickAndImportImages(
        store: widget.attachments,
        source: source,
      );
      if (!mounted || added.isEmpty) return;
      setState(() {
        _names.addAll(added);
        _pickError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _pickError = '选图失败：$e');
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _committed = true;
      await widget.sender.composeAndSend(
        type: _type,
        content: text,
        assignee: widget.assignee,
        attachments: List<String>.from(_names),
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
      title: Text(widget.assignee.isEmpty ? '💭 待定 · 记一条' : '给 ${widget.assignee} 加任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<MsgType>(
              segments: const [
                ButtonSegment(value: MsgType.task, label: Text('任务')),
                ButtonSegment(value: MsgType.note, label: Text('随手记')),
                ButtonSegment(value: MsgType.bookmark, label: Text('网址')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: '内容……', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _sending ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('相册'),
                ),
                TextButton.icon(
                  onPressed: _sending ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照'),
                ),
              ],
            ),
            AttachmentThumbStrip(
              store: widget.attachments,
              names: _names,
              size: 56,
              onRemove: _sending
                  ? null
                  : (n) {
                      setState(() => _names.remove(n));
                      unawaited(widget.attachments.deleteNamed([n]));
                    },
            ),
            if (_pickError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_pickError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? '发送中' : '记下并送出')),
      ],
    ),
    );
  }
}

/// 点条目看详情：全文 + 本地图（可再贴/去掉）。改图只动手机本地，不重发邮局。
class _EntryDetailDialog extends StatefulWidget {
  const _EntryDetailDialog({
    required this.entry,
    required this.store,
    required this.attachments,
  });

  final LedgerEntry entry;
  final LedgerStore store;
  final AttachmentStore attachments;

  @override
  State<_EntryDetailDialog> createState() => _EntryDetailDialogState();
}

class _EntryDetailDialogState extends State<_EntryDetailDialog> {
  late List<String> _names;
  String? _pickError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _names = List<String>.from(widget.entry.attachments);
  }

  Future<void> _persist(List<String> next) async {
    await widget.store.updateAttachments(widget.entry.id!, next);
    if (mounted) setState(() => _names = next);
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy || widget.entry.id == null) return;
    setState(() => _busy = true);
    try {
      final added = await pickAndImportImages(
        store: widget.attachments,
        source: source,
      );
      if (added.isEmpty) return;
      await _persist([..._names, ...added]);
      if (mounted) setState(() => _pickError = null);
    } catch (e) {
      if (mounted) setState(() => _pickError = '选图失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String name) async {
    if (_busy || widget.entry.id == null) return;
    setState(() => _busy = true);
    try {
      await widget.attachments.deleteNamed([name]);
      await _persist(_names.where((n) => n != name).toList());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('条目'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(widget.entry.content, style: const TextStyle(height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('相册'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照'),
                ),
              ],
            ),
            AttachmentThumbStrip(
              store: widget.attachments,
              names: _names,
              size: 72,
              onRemove: _busy ? null : _remove,
            ),
            if (_names.isEmpty)
              Text('还没有图。相册或拍照贴上，只存在这台手机。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (_pickError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_pickError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭')),
      ],
    );
  }
}
