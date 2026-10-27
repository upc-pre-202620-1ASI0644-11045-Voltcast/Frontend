class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.status,
    this.role,
    this.createdAt,
  });

  final int id;
  final String email;
  final String fullName;

  /// `pending`, `active`, `rejected` or `disabled`.
  final String status;

  /// `ADMIN` (Supervisor) or `USER` (Ingeniero de Planta); null until approved.
  final String? role;

  final DateTime? createdAt;

  bool get isAdmin => role == 'ADMIN';
  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isDisabled => status == 'disabled';

  /// Supervisor accounts cannot be edited or disabled from the app (the
  /// backend only manages engineer accounts).
  bool get isManageable => !isAdmin;

  String get roleLabel => switch (role) {
        'ADMIN' => 'Supervisor',
        'USER' => 'Ingeniero de Planta',
        _ => 'Sin rol asignado',
      };

  /// "Mariana Torres" -> "MT"; a single name gives one letter.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        status: json['status'] as String,
        role: json['role'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}
