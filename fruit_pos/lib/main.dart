import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/api_service.dart';
import 'auth/auth_repository.dart';
import 'auth/auth_state.dart';
import 'core/theme.dart';
import 'dart:async';
import 'core/constants.dart';
import 'database/app_database.dart';
import 'features/damage/damage_list_page.dart';
import 'features/damage/new_damage_report_page.dart';
import 'features/dashboard/home_shell.dart';
import 'features/login/login_page.dart';
import 'features/products/products_page.dart';
import 'features/reports/reports_page.dart';
import 'features/reports/sales_report_page.dart';
import 'features/reports/stock_report_page.dart';
import 'features/reports/profit_report_page.dart';
import 'features/sales/sales_page.dart';
import 'features/stock/stock_page.dart';
import 'features/audit/audit_log_page.dart';
import 'features/employees/employees_page.dart';
import 'features/settings/exit_approvals_page.dart';
import 'features/splash/splash_page.dart';
import 'features/transactions/transactions_page.dart';
import 'sync/connectivity_service.dart';
import 'sync/sync_manager.dart';
import 'services/exit_attempt_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  final apiClient = ApiClient();
  final apiService = ApiService(apiClient);
  final authRepository = AuthRepository(
    apiClient: apiClient,
    apiService: apiService,
  );
  final authState = AuthState(repository: authRepository);

  final db = AppDatabase.instance;
  final syncManager = SyncManager(
    apiService: apiService,
    outboxDao: db.outbox,
    productsDao: db.products,
    salesDao: db.sales,
    damageDao: db.damage,
  );
  final connectivity = ConnectivityService();
  await connectivity.initialize();

  await authState.initialize();
  await syncManager.syncNow();
  await syncManager.startPeriodicSync();

  runApp(
    FruitPosApp(
      authState: authState,
      apiService: apiService,
      apiClient: apiClient,
      syncManager: syncManager,
      connectivity: connectivity,
    ),
  );
}

class FruitPosApp extends StatelessWidget {
  final AuthState authState;
  final ApiService apiService;
  final ApiClient apiClient;
  final SyncManager syncManager;
  final ConnectivityService connectivity;

  const FruitPosApp({
    super.key,
    required this.authState,
    required this.apiService,
    required this.apiClient,
    required this.syncManager,
    required this.connectivity,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>.value(value: authState),
        Provider<ApiService>.value(value: apiService),
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<SyncManager>.value(value: syncManager),
        Provider<ConnectivityService>.value(value: connectivity),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder:
            (context, child) =>
                ExitAttemptListener(child: child ?? const SizedBox.shrink()),
        initialRoute: '/',
        routes: {
          '/': (_) => const AuthGate(),
          '/sales': (_) => const SalesPage(),
          '/products': (_) => const ProductsPage(),
          '/damage/new': (_) => const NewDamageReportPage(),
          '/damage/list': (_) => const DamageListPage(),
          '/transactions': (_) => const TransactionsPage(),
          '/reports': (_) => const ReportsPage(),
          '/reports/sales': (_) => const SalesReportPage(),
          '/reports/stock': (_) => const StockReportPage(),
          '/reports/profit': (_) => const ProfitReportPage(),
          '/stock': (_) => const StockPage(),
          '/audit': (_) => const AuditLogPage(),
          '/employees': (_) => const EmployeesPage(),
          '/exit-approvals': (_) => const ExitApprovalsPage(),
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    if (!_splashDone) {
      return SplashPage(
        onDone: () {
          if (mounted) setState(() => _splashDone = true);
        },
      );
    }

    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.unauthenticated:
        return const LoginPage();
      case AuthStatus.authenticated:
        return const HomeShell();
    }
  }
}
