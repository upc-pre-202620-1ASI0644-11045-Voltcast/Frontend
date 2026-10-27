import 'package:actualvoltcast/core/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('accepts a normal address', () => expect(Validators.email('a@b.co'), isNull));
    test('rejects empty and malformed', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('sin-arroba'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
    });
  });

  group('newPassword mirrors the backend policy', () {
    test('accepts upper, lower, digit, symbol and 8+ chars', () {
      expect(Validators.newPassword('SecurePass123!'), isNull);
    });

    test('rejects each missing rule', () {
      expect(Validators.newPassword('Ab1!'), isNotNull); // too short
      expect(Validators.newPassword('securepass123!'), isNotNull); // no uppercase
      expect(Validators.newPassword('SECUREPASS123!'), isNotNull); // no lowercase
      expect(Validators.newPassword('SecurePass!!!!'), isNotNull); // no digit
      expect(Validators.newPassword('SecurePass1234'), isNotNull); // no symbol
    });

    test('rejects more than 128 characters', () {
      expect(Validators.newPassword('Aa1!${'x' * 130}'), isNotNull);
    });
  });

  test('passwordStrength scores 0..4', () {
    expect(Validators.passwordStrength(''), 0);
    expect(Validators.passwordStrength('abcdefgh'), 1);
    expect(Validators.passwordStrength('Abcdefgh'), 2);
    expect(Validators.passwordStrength('Abcdefg1'), 3);
    expect(Validators.passwordStrength('Abcdef1!'), 4);
  });

  test('confirmPassword compares against the original', () {
    final validate = Validators.confirmPassword(() => 'Secret123!');
    expect(validate('Secret123!'), isNull);
    expect(validate('other'), isNotNull);
    expect(validate(''), isNotNull);
  });

  test('verificationCode needs exactly 6 digits', () {
    expect(Validators.verificationCode('123456'), isNull);
    expect(Validators.verificationCode('12345'), isNotNull);
    expect(Validators.verificationCode('12345a'), isNotNull);
  });
}
