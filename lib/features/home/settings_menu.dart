import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// What the gear of the tab headers does: open the control center.
VoidCallback settingsAction(BuildContext context) =>
    () => context.push('/settings');
