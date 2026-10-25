import 'package:flutter/material.dart';

import 'network/api_exception.dart';
import 'theme/app_theme.dart';

/// Confirmation dialog. Returns true when the user confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  Color actionColor = AppColors.error,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: actionColor),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Runs [action] and reports the outcome in a SnackBar: [done] on success,
/// the error message on [ApiException].
Future<void> runAction(BuildContext context, Future<void> Function() action, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: builder,
  );
}
