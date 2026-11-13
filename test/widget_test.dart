// Keeps `flutter create` from generating its own template widget test (that template does not match this app).
import 'package:culinex/core/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English and Bahasa Melayu strings resolve; unknown keys fall back to the key', () {
    const en = T('en');
    const ms = T('ms');
    expect(en('nav_home'), 'Home');
    expect(ms('nav_home'), 'Utama');
    expect(en('disclaimer_profit').contains('NOT NET PROFIT'), isTrue);
    expect(ms('disclaimer_profit').contains('BUKAN UNTUNG BERSIH'), isTrue);
    expect(en('no_such_key'), 'no_such_key');
    // placeholders used by the UI
    expect(en('low_stock_banner').contains('{n}'), isTrue);
    expect(ms('low_stock_banner').contains('{n}'), isTrue);
  });
}
