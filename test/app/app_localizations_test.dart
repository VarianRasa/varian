import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:varian/app/localization/app_localizations.dart';

void main() {
  test('supports English and Indonesian strings', () async {
    final english = await CreativeStudioLocalizations.delegate.load(
      const Locale('en'),
    );
    final indonesian = await CreativeStudioLocalizations.delegate.load(
      const Locale('id'),
    );

    expect(english.save, 'Save');
    expect(indonesian.save, 'Simpan');
    expect(indonesian.importTitle, 'Impor diagram / dokumen');
  });
}
