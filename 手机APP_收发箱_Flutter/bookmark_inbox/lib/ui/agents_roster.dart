// ---
// 这是啥: 看板分组名单——agent 名单的本地持久化（无限加组）
// 谁看: AgentBoardPage（读名单/加组）
// 什么时候用: 看板分组、长按移动条目
// 改之前必看: 名单只是看板展示顺序的依据，账本条目的 assignee 字段才是分组事实；
//   名单里删掉的组不删数据，条目仍按 assignee 原值归入「其他」
// ---
import 'package:shared_preferences/shared_preferences.dart';

class AgentRoster {
  AgentRoster({this.defaultNames = _defaults});

  static const _defaults = ['Claude', 'ChatGPT', 'Pi Agent', 'Antigravity', 'Hermes']; // 没拉到电脑看板时的兜底，跟电脑默认五组一样
  static const _kNames = 'board.agents';

  final List<String> defaultNames;

  Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList(_kNames);
    if (saved == null || saved.isEmpty) return List.of(defaultNames);
    return saved;
  }

  Future<void> save(List<String> names) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kNames, names);
  }
}
