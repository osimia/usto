import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/usto_app.dart';

void main() {
  testWidgets('renders USTO auth screen', (tester) async {
    await tester.pumpWidget(const UstoApp());

    expect(find.text('Опишите задачу'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
    expect(find.text('Далее ->'), findsOneWidget);
  });
}
