import 'package:flutter/widgets.dart';

import 'network/api_exception.dart';

/// Loading + error handling shared by every form screen.
mixin SubmitState<T extends StatefulWidget> on State<T> {
  bool loading = false;
  String? error;

  /// Runs [action]; returns true on success. [ApiException]s become [error].
  Future<bool> submit(Future<void> Function() action) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
