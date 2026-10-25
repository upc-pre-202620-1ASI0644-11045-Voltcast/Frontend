/// Messages the screens react to (not just display).
const cellHasComponentsMessage = 'La celda tiene componentes asignados. Libéralos antes de eliminarla.';
const invalidCodeMessage = 'El código es inválido o ya expiró. Solicita uno nuevo.';

/// The backend answers in English; the app is in Spanish. Exact messages are
/// looked up first, then prefix patterns for messages that embed values.
const _exact = {
  'Invalid credentials': 'Correo o contraseña incorrectos.',
  'Your account request is pending approval':
      'Tu solicitud de cuenta aún está pendiente de aprobación.',
  'Your account request was rejected': 'Tu solicitud de cuenta fue rechazada.',
  'Your account is disabled': 'Tu cuenta está deshabilitada.',
  'Invalid or expired verification code': invalidCodeMessage,
  'Invalid or expired refresh token': 'Tu sesión expiró. Inicia sesión de nuevo.',
  'User not found or account is not active': 'Tu cuenta ya no está disponible.',
  'Not authenticated': 'Tu sesión expiró. Inicia sesión de nuevo.',
  'Only pending requests can be approved': 'Esta solicitud ya fue procesada.',
  'Only pending requests can be rejected': 'Esta solicitud ya fue procesada.',
  'Only active accounts can be disabled':
      'La cuenta ya no está activa. Actualiza la lista.',
  'Only disabled accounts can be enabled':
      'La cuenta ya no está deshabilitada. Actualiza la lista.',
  'Only registered engineer accounts can be edited or disabled':
      'Solo se pueden editar o deshabilitar cuentas de ingenieros.',
  // Cells and components
  'Cell name must be a letter followed by a number, e.g. A1, B12':
      'El nombre debe ser una letra seguida de un número, por ejemplo A1 o B12.',
  'Cell has assigned cathodes/anodes; release them before removing it': cellHasComponentsMessage,
  'Cell must have an assigned cathode and anode to generate its barcode':
      'La celda necesita un cátodo y un ánodo asignados para generar su código.',
  'Cannot generate a barcode for an inactive cell':
      'La celda necesita un cátodo y un ánodo asignados para generar su código.',
  'Cannot assign a disabled component': 'No se puede asignar un componente deshabilitado.',
  'Component is in use: it is assigned to a cell':
      'El componente está en uso: está asignado a una celda y no se puede deshabilitar.',
  'Component is already disabled': 'El componente ya está deshabilitado.',
  'Component is already active': 'El componente ya está activo.',
  'Only a disabled component can be removed from view': 'Solo se puede eliminar un componente deshabilitado.',
  'Can only swap components of the same type (CATHODE with CATHODE, ANODE with ANODE)':
      'Solo se pueden intercambiar componentes del mismo tipo.',
  'Both components must be assigned to a cell to be swapped':
      'Ambos componentes deben estar asignados a una celda.',
  'Components belong to the same cell': 'Los componentes pertenecen a la misma celda.',
  'Cell not found': 'La celda no existe.',
  'Component not found': 'El componente no existe.',
};

final _cellExists = RegExp(r"^Cell '.*' already exists$");
final _serialExists = RegExp(r"^Component with serial code '.*' already exists$");
final _notFound = RegExp(r'^(Cell|Component) not found: \d+$');

final _alreadyRegistered = RegExp(r"^Email '.*' is already registered$");
final _tooManyRequests = RegExp(r'^Too many requests\. Try again in (\d+) seconds\.$');

String translateBackendMessage(String message) {
  final exact = _exact[message];
  if (exact != null) return exact;

  if (_alreadyRegistered.hasMatch(message)) {
    return 'Este correo ya está registrado o tiene una solicitud en curso.';
  }
  if (_cellExists.hasMatch(message)) return 'Ya existe una celda con ese nombre.';
  if (_serialExists.hasMatch(message)) return 'Ya existe un componente con ese código de serie.';
  final missing = _notFound.firstMatch(message);
  if (missing != null) {
    return missing.group(1) == 'Cell' ? 'La celda no existe.' : 'El componente no existe.';
  }
  final wait = _tooManyRequests.firstMatch(message);
  if (wait != null) {
    final seconds = int.parse(wait.group(1)!);
    final text = seconds >= 60 ? '${(seconds / 60).ceil()} minutos' : '$seconds segundos';
    return 'Demasiados intentos. Inténtalo de nuevo en $text.';
  }
  if (message.startsWith('Password must contain')) {
    return 'La contraseña debe tener 8 caracteres, mayúscula, minúscula, '
        'número y un carácter especial.';
  }
  return message;
}
