/// Client-side mirrors of the backend rules, so the user gets feedback before
/// a round trip. The backend remains the source of truth.
class Validators {
  Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo electrónico.';
    if (!_email.hasMatch(v)) return 'Ingresa un correo válido.';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Ingresa tu nombre completo.';
    if (v.length > 200) return 'El nombre es demasiado largo.';
    return null;
  }

  /// Same rule as `Cell.normalize_name`: a letter followed by a number.
  static String? cellName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa el nombre de la celda.';
    if (!RegExp(r'^[A-Za-z][1-9][0-9]*$').hasMatch(v)) {
      return 'Usa una letra seguida de un número, por ejemplo A1 o B12.';
    }
    return null;
  }

  static String? serialCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa el código de serie.';
    if (v.length > 50) return 'Máximo 50 caracteres.';
    return null;
  }

  static String? required(String? value, [String message = 'Campo obligatorio.']) {
    return (value == null || value.isEmpty) ? message : null;
  }

  /// Same policy as `User.validate_password_policy` in the backend.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Crea una contraseña.';
    if (v.length > 128) return 'Máximo 128 caracteres.';
    if (passwordStrength(v) < 4) {
      return 'Usa 8+ caracteres, mayúscula, minúscula, número y símbolo.';
    }
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return 'Repite tu contraseña.';
      if (value != original()) return 'Las contraseñas no coinciden.';
      return null;
    };
  }

  static String? verificationCode(String? value) {
    if (value == null || !RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'El código tiene 6 dígitos.';
    }
    return null;
  }

  /// 0..4 — one point per rule group of the backend policy. 4 means valid.
  static int passwordStrength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score;
  }
}
