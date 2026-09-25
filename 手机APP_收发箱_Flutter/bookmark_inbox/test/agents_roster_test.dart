// ---
// 这是啥: 分组名单存取测试——默认四家、保存后读回、清空回落默认
// 谁看: 改 agents_roster.dart 的人
// ---
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookmark_inbox/ui/agents_roster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没存过=默认四家；存了读回原样', () async {
    SharedPreferences.setMockInitialValues({});
    final roster = AgentRoster();
    expect(await roster.load(), ['Claude', 'ChatGPT', 'Pi Agent', 'Antigravity', 'Hermes']);

    await roster.save(['Claude', 'Codex']);
    expect(await roster.load(), ['Claude', 'Codex']);
  });

  test('存空名单也回落默认（不许看板变成无组白屏）', () async {
    SharedPreferences.setMockInitialValues({'board.agents': <String>[]});
    final roster = AgentRoster();
    expect(await roster.load(), isNotEmpty);
  });
}
