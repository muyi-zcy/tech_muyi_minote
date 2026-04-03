import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:tech_muyi_minote/main.dart';

void main() {
  testWidgets('小米风格笔记页加载 SuperEditor', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(SuperEditor), findsOneWidget);
    expect(find.textContaining('字'), findsOneWidget);
  });
}
