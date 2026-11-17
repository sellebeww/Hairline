import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hairline/main.dart';

void main() {
  testWidgets('app boots and shows the core version', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HairlineApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hairline core 0.1.0'), findsOneWidget);
  });
}
