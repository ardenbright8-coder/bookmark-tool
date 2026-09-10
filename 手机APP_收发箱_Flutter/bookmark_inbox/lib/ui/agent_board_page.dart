// ---
// 这是啥: Agent 看板主页——单页按 agent 分组展示全部条目（用户拍板的正式形态）
// 谁看: main 的唯一 home
// 什么时候用: 打开 APP 即看板
// 改之前必看: 分组事实=条目 assignee 字段（空=💭待定置顶）；名单只是展示顺序；
//   组头⊕加任务（弹窗）、折叠箭头只折 UI 不动数据；长按条目=移动分组/删除；
//   任务行右侧不放任何按钮（用户拍板：自动同步无需手动确认）
// ---
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/ledger.dart';
import '../core/models.dart';
import '../core/receipt_sync.dart';
import '../core/sender.dart';
import 'agents_roster.dart';
import 'settings_dialog.dart';

const _pendingKey = '__pending__';

class AgentBoardPage extends StatefulWidget {
  const AgentBoardPage({
    super.key,
    required this.store,
    required this.sender,
    required this.receiptSync,
    required this.revision,
    required this.onChanged,
  });

  final LedgerStore store;
  final Sender sender;
  final ReceiptSync receiptSync;
  final int revision; // main 侧数据版本号，变了就重拉
  final VoidCallback onChanged;

  @override
  State<AgentBoardPage> createState() => _AgentBoardPageState();
}

class _AgentBoardPageState extends State<AgentBoardPage> {
  List<LedgerEntry> _entries = [];
  List<String> _agents = [];
  final Set<String> _collapsed = {};
  int _lastRevision = -1;
  final AgentRoster _roster = AgentRoster();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AgentBoardPage old) {
    super.didUpdateWidget(old);
    if (widget.revision != _lastRevision) _reload();
  }

  Future<void> _reload() async {
    _lastRevision = widget.revision;
    final entries = await widget.store.entries();
    final agents = await _roster.load();
    if (mounted) {
      setState(() {
        _entries = entries;
        _agents = agents;
      });
    }
  }

  /// 分组：💭待定置顶 → 名单顺序 → 名单外老数据归入「其他」
  List<(String key, String name, List<LedgerEntry> items)> _groups() {
    final groups = <(String, String, List<LedgerEntry>)>[];
    groups.add((
      _pendingKey,
      '待定（想想区）',
      _entries.where((e) => e.assignee.isEmpty).toList(),
    ));
    for (final a in _agents) {
      groups.add((a, a, _entries.where((e) => e.assignee == a).toList()));
    }
    final known = <String>{'', ..._agents};
    final extras = _entries
        .map((e) => e.assignee)
        .where((a) => a.isNotEmpty && !known.contains(a))
        .toSet();
    for (final a in extras) {
      groups.add((a, a, _entries.where((e) => e.assignee == a).toList()));
    }
    return groups;
  }

  Future<void> _refreshAll() async {
    final cfg = await ChannelConfig.load();
    await widget.sender.retryPending();
    await widget.receiptSync.sync(cfg);
    await _reload();
  }

  Future<void> _quickAdd(String assignee) async {
    final typeContent = await showDialog<(MsgType, String)>(
      context: context,
      builder: (_) => _QuickTaskDialog(
            assignee: assignee,
            sender: widget.sender,
          ),
    );
    if (typeContent == null) return;
    await widget.sender.composeAndSend(
      type: typeContent.$1,
      content: typeContent.$2,
      assignee: assignee,
    );
    setState(() => _collapsed.remove(assignee.isEmpty ? _pendingKey : assignee));
    widget.onChanged();
    await _reload();
  }

  Future<void> _addAgent() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('添加分组'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Agent 名称', hintText: '如 Codex、Gemini……'),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                child: const Text('添加')),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    if (_agents.contains(name)) return;
    final next = [..._agents, name];
    await _roster.save(next);
    await _reload();
  }

  Future<void> _moveEntry(LedgerEntry e) async {
    final targets = <(String, String)>[
      (_pendingKey, '💭 待定（想想区）'),
      ..._agents.map((a) => (a, a)),
      if (e.assignee.isNotEmpty && !_agents.contains(e.assignee))
        (e.assignee, e.assignee),
    ];
    final choice = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('移动到……', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final (key, name) in targets)
              if (key != (e.assignee.isEmpty ? _pendingKey : e.assignee))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: Text(name),
                  onTap: () => Navigator.of(ctx).pop((key, name)),
                ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除记录', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop(('__delete__', '')),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice.$1 == '__delete__') {
      await widget.store.deleteEntry(e.id!);
    } else {
      final assignee = choice.$1 == _pendingKey ? '' : choice.$1;
      await widget.store.updateAssignee(e.id!, assignee);
    }
    widget.onChanged();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4EA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(children: [
          Icon(Icons.wb_sunny_outlined, size: 22),
          SizedBox(width: 8),
          Text('Agent 看板', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            tooltip: '邮局设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showDialog(
                context: context, builder: (_) => const SettingsDialog()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: groups.length + 1,
          itemBuilder: (context, i) {
            if (i == groups.length) return _addAgentTile();
            final (key, name, items) = groups[i];
            return _groupCard(key, name, items);
          },
        ),
      ),
    );
  }

  Widget _addAgentTile() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OutlinedButton.icon(
        onPressed: _addAgent,
        icon: const Icon(Icons.add),
        label: const Text('添加分组'),
      ),
    );
  }

  Widget _groupCard(String key, String name, List<LedgerEntry> items) {
    final collapsed = _collapsed.contains(key);
    final isPending = key == _pendingKey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
            leading: _avatar(name, isPending),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => setState(() => _toggle(key)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: isPending ? '记一条待定' : '给 $name 加任务',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _quickAdd(isPending ? '' : key),
                ),
                IconButton(
                  tooltip: collapsed ? '展开' : '折叠',
                  icon: Icon(collapsed
                      ? Icons.keyboard_arrow_right
                      : Icons.keyboard_arrow_down),
                  onPressed: () => setState(() => _toggle(key)),
                ),
              ],
            ),
          ),
          if (!collapsed) ...[
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(isPending ? '想到啥先扔这，想好给谁再移过去。' : '这组还没有任务。',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ),
              )
            else
              for (var i = 0; i < items.length; i++)
                _taskRow(items[i], i),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  void _toggle(String key) {
    _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
  }

  Widget _taskRow(LedgerEntry e, int index) {
    final (color, label) = switch (e.status) {
      SendStatus.confirmed => (const Color(0xFF6E9E6E), '电脑已收录'),
      SendStatus.sent => (const Color(0xFF7FA6C2), '已送出·待回执'),
      SendStatus.pending => (const Color(0xFFD29B4B), '待发送'),
    };
    final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onLongPress: () => _moveEntry(e),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.25),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$label · $hh:$mm'
                    '${e.status == SendStatus.pending && e.attempts > 0 ? '（失败${e.attempts}次）' : ''}'
                    '${e.lastError.isEmpty ? '' : ' · ${e.lastError}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String name, bool isPending) {
    if (isPending) {
      return Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0xFFE7E9D8)),
        child: const Text('💭', style: TextStyle(fontSize: 18)),
      );
    }
    const palette = [
      [Color(0xFFF0C987), Color(0xFFE0A94B)],
      [Color(0xFF9CC29C), Color(0xFF6E9E6E)],
      [Color(0xFFA8C5D8), Color(0xFF7FA6C2)],
      [Color(0xFFD8B4C0), Color(0xFFC291A5)],
      [Color(0xFFC9B6E4), Color(0xFFA78BD4)],
    ];
    final c = palette[name.hashCode.abs() % palette.length];
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
    );
  }
}

/// 组头⊕弹的快速加任务窗：类型三选（默认任务），发送走 Sender（先落账本）
class _QuickTaskDialog extends StatefulWidget {
  const _QuickTaskDialog({required this.assignee, required this.sender});

  final String assignee; // 空串=待定组
  final Sender sender;

  @override
  State<_QuickTaskDialog> createState() => _QuickTaskDialogState();
}

class _QuickTaskDialogState extends State<_QuickTaskDialog> {
  final _ctrl = TextEditingController();
  MsgType _type = MsgType.task;
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.sender.composeAndSend(
          type: _type, content: text, assignee: widget.assignee);
      if (mounted) Navigator.of(context).pop((MsgType.task, text));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.assignee.isEmpty ? '💭 待定 · 记一条' : '给 ${widget.assignee} 加任务'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
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
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? '发送中' : '记下并送出')),
      ],
    );
  }
}
