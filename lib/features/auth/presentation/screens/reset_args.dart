/// Passed between the password-recovery screens through go_router `extra`,
/// so the email and code never appear in a URL.
class ResetArgs {
  const ResetArgs({required this.email, required this.code});

  final String email;
  final String code;
}
