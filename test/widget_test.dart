import 'package:flutter_test/flutter_test.dart';
import 'package:airport_mobile/main.dart';

void main() {
  testWidgets('显示登录页品牌与入口', (tester) async {
    await tester.pumpWidget(const AirportApp());
    expect(find.text('ClashNova'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.textContaining('控制面'), findsWidgets);
  });
}
