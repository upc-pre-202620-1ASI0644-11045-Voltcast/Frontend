import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/cells/data/inventory_repository.dart';
import 'features/users/data/users_repository.dart';

class VoltCastApp extends StatefulWidget {
  const VoltCastApp({super.key});

  @override
  State<VoltCastApp> createState() => _VoltCastAppState();
}

class _VoltCastAppState extends State<VoltCastApp> {
  late final ApiClient _api;
  late final AuthRepository _repository;
  late final UsersRepository _users;
  late final InventoryRepository _inventory;
  late final AuthController _auth;
  late final _router = buildRouter(_auth);

  @override
  void initState() {
    super.initState();
    final tokens = TokenStorage();
    _api = ApiClient(tokenStorage: tokens);
    _repository = AuthRepository(api: _api, tokens: tokens);
    _users = UsersRepository(_api);
    _inventory = InventoryRepository(_api);
    _auth = AuthController(_repository);
    _api.onSessionExpired = _auth.handleSessionExpired;
    _auth.restoreSession();
  }

  @override
  void dispose() {
    _router.dispose();
    _auth.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: _repository),
        Provider<UsersRepository>.value(value: _users),
        Provider<InventoryRepository>.value(value: _inventory),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
      ],
      child: MaterialApp.router(
        title: 'VoltCast',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
