/// Messages the screens react to (not just display).
const cellHasComponentsMessage =
    'La celda tiene componentes asignados. Libéralos antes de eliminarla.';
const invalidCodeMessage =
    'El código es inválido o ya expiró. Solicita uno nuevo.';

/// The backend answers in English; the app is in Spanish. Exact messages are
/// looked up first, then prefix patterns for messages that embed values.
const _exact = {
  'Invalid credentials': 'Correo o contraseña incorrectos.',
  'Your account request is pending approval':
      'Tu solicitud de cuenta aún está pendiente de aprobación.',
  'Your account request was rejected': 'Tu solicitud de cuenta fue rechazada.',
  'Your account is disabled': 'Tu cuenta está deshabilitada.',
  'Invalid or expired verification code': invalidCodeMessage,
  'Invalid or expired refresh token':
      'Tu sesión expiró. Inicia sesión de nuevo.',
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
  'Cell name must be a letter followed by a number, e.g. A1, B12': 'El nombre debe ser una letra seguida de un número, por ejemplo A1 o B12.',
  'Cell has assigned cathodes/anodes; release them before removing it':
      cellHasComponentsMessage,
  'Cell must have an assigned cathode and anode to generate its barcode': 'La celda necesita un cátodo y un ánodo asignados para generar su código.',
  'Cannot generate a barcode for an inactive cell': 'La celda necesita un cátodo y un ánodo asignados para generar su código.',
  'Cannot assign a disabled component':
      'No se puede asignar un componente deshabilitado.',
  'Component is in use: it is assigned to a cell': 'El componente está en uso: está asignado a una celda y no se puede deshabilitar.',
  'Component is already disabled': 'El componente ya está deshabilitado.',
  'Component is already active': 'El componente ya está activo.',
  'Only a disabled component can be removed from view':
      'Solo se puede eliminar un componente deshabilitado.',
  'Can only swap components of the same type (CATHODE with CATHODE, ANODE with ANODE)':
      'Solo se pueden intercambiar componentes del mismo tipo.',
  'Both components must be assigned to a cell to be swapped':
      'Ambos componentes deben estar asignados a una celda.',
  'Components belong to the same cell':
      'Los componentes pertenecen a la misma celda.',
  'Cell not found': 'La celda no existe.',
  'Component not found': 'El componente no existe.',
  // Datasets, trainings and forecasts
  'The file is empty': 'El archivo está vacío.',
  'Dataset not found': 'El archivo no existe.',
  'A training is already in progress': 'Ya hay un entrenamiento en curso. Espera a que termine para iniciar otro.',
  'A training is in progress; wait for it to finish before uploading a new file':
      'Hay un entrenamiento en curso; espera a que termine para subir un archivo.',
  'The dataset to complement does not exist or is not ready':
      'El archivo que quieres complementar no existe o aún no está listo.',
  'The end date cannot be before the start date':
      'La fecha final no puede ser anterior a la inicial.',
  'Maximum voltage must be greater than zero':
      'El voltaje máximo debe ser mayor que cero.',
};

final _cellExists = RegExp(r"^Cell '.*' already exists$");
final _serialExists = RegExp(
  r"^Component with serial code '.*' already exists$",
);
final _notFound = RegExp(r'^(Cell|Component) not found: \d+$');

final _unsupportedFormat = RegExp(r'^Unsupported file format');
final _tooBig = RegExp(r'^The file exceeds the (\d+) MB limit$');
final _datasetNotFound = RegExp(r'^Dataset not found: \d+$');
final _datasetNotReady = RegExp(r'^The dataset is not ready to train');

/// Why a file was rejected (`error_message` of a `failed` dataset).
final _rejections = <(RegExp, String Function(Match))>[
  (
    RegExp(r'^The file has dates after today'),
    (_) => 'El archivo tiene fechas posteriores a hoy. Solo se pueden subir voltajes ya medidos.',
  ),
  (
    RegExp(r'^The file covers (\d+) days; at least (\d+) are needed'),
    (m) => 'El archivo cubre solo ${m[1]} días; se necesitan al menos ${m[2]}.',
  ),
  (
    RegExp(r'^Merged, the files cover (\d+) days; at least (\d+) are needed'),
    (m) => 'Juntos, los archivos cubren solo ${m[1]} días; se necesitan al menos ${m[2]}.',
  ),
  (
    RegExp(r'^There are (\d+) days without records between .* at most (\d+) can be bridged'),
    (m) => 'Hay ${m[1]} días sin registros entre el archivo base y el nuevo; como máximo se pueden cubrir ${m[2]}.',
  ),
  (
    RegExp(r'^The file adds no days after'),
    (_) => 'El archivo no aporta ningún día nuevo respecto al archivo base.',
  ),
  (
    RegExp(r'^The (sections|cells) of'),
    (_) => 'Las celdas o secciones del archivo son distintas a las del archivo base.',
  ),
];

final _alreadyRegistered = RegExp(r"^Email '.*' is already registered$");
final _tooManyRequests = RegExp(
  r'^Too many requests\. Try again in (\d+) seconds\.$',
);

String translateBackendMessage(String message) {
  final exact = _exact[message];
  if (exact != null) return exact;

  if (_alreadyRegistered.hasMatch(message)) {
    return 'Este correo ya está registrado o tiene una solicitud en curso.';
  }
  if (_cellExists.hasMatch(message)) {
    return 'Ya existe una celda con ese nombre.';
  }
  if (_serialExists.hasMatch(message)) {
    return 'Ya existe un componente con ese código de serie.';
  }
  final missing = _notFound.firstMatch(message);
  if (missing != null) {
    return missing.group(1) == 'Cell'
        ? 'La celda no existe.'
        : 'El componente no existe.';
  }
  if (_unsupportedFormat.hasMatch(message)) {
    return 'El formato no es compatible. Sube un archivo de Excel (.xlsx o .xlsm).';
  }
  final big = _tooBig.firstMatch(message);
  if (big != null) return 'El archivo supera el límite de ${big.group(1)} MB.';
  if (_datasetNotFound.hasMatch(message)) return 'El archivo no existe.';
  if (_datasetNotReady.hasMatch(message)) {
    return 'El archivo aún no está listo para entrenar. Espera a que termine de procesarse.';
  }
  for (final (pattern, text) in _rejections) {
    final m = pattern.firstMatch(message);
    if (m != null) return text(m);
  }
  final wait = _tooManyRequests.firstMatch(message);
  if (wait != null) {
    final seconds = int.parse(wait.group(1)!);
    final text = seconds >= 60
        ? '${(seconds / 60).ceil()} minutos'
        : '$seconds segundos';
    return 'Demasiados intentos. Inténtalo de nuevo en $text.';
  }
  if (message.startsWith('Password must contain')) {
    return 'La contraseña debe tener 8 caracteres, mayúscula, minúscula, '
        'número y un carácter especial.';
  }
  return message;
}
