// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ska_app/main.dart';

void main() {
  testWidgets('Login flow navigates to marketing home', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Pastikan form login ditampilkan
    expect(find.text('Selamat Datang'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    // Isi form login
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'marketing@ska.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );

    // Tekan tombol login
    await tester.tap(find.text('Login'));
    await tester.pump();

    // Tunggu animasi loading dan navigasi selesai
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Halaman home marketing harus muncul
    expect(find.text('Marketing Center'), findsOneWidget);
    expect(find.text('Daftar Customer'), findsOneWidget);
    expect(find.text('Tambah'), findsOneWidget);
  });
}
