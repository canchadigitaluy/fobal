import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/main.dart';
import 'package:cantera_os/screens/reservas_screen.dart';

void main() {
  testWidgets('shows login screen on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const CanteraApp());

    expect(find.text('CanteraOS'), findsOneWidget);
    expect(find.text('Ingresar a CanteraOS'), findsOneWidget);
  });

  testWidgets('assistant requires club context before planning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      AppScope(
        club: canteraDemoClub,
        fullClub: canteraDemoClub,
        role: UserRole.coordinator,
        selectedCategoryId: canteraDemoClub.categories.isEmpty
            ? null
            : canteraDemoClub.categories.first.id,
        selectRole: (_) {},
        selectCategory: (_) {},
        updateClub: (_) {},
        loadClub: (_) => canteraDemoClub,
        child: const MaterialApp(home: ReservasScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asistente de juego'), findsOneWidget);
    expect(find.text('Categoria: Categoria sin cargar.'), findsOneWidget);
    expect(find.text('Generar sesion'), findsOneWidget);
  });
}
