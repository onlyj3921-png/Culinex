import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'state/providers.dart';
import 'ui/calculator_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/expenses_screen.dart';
import 'ui/ingredients_screen.dart';
import 'ui/more_screen.dart';
import 'ui/recipes_screen.dart';
import 'ui/reports_screen.dart';
import 'ui/sales_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/stock_screen.dart';

final _router = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _Shell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (c, s) => const DashboardScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/calculator', builder: (c, s) => const CalculatorScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/recipes', builder: (c, s) => const RecipesScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/sales', builder: (c, s) => const SalesScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (c, s) => const MoreScreen())]),
      ],
    ),
    GoRoute(path: '/recipe/:id', builder: (c, s) => RecipeEditorScreen(idParam: s.pathParameters['id']!)),
    GoRoute(path: '/ingredients', builder: (c, s) => const IngredientsScreen()),
    GoRoute(path: '/ingredient/:id', builder: (c, s) => IngredientEditorScreen(idParam: s.pathParameters['id']!)),
    GoRoute(path: '/stock', builder: (c, s) => const StockScreen()),
    GoRoute(path: '/expenses', builder: (c, s) => const ExpensesScreen()),
    GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
  ],
);

class CulinexApp extends ConsumerWidget {
  const CulinexApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'CULINEX',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: t('nav_home')),
          NavigationDestination(icon: const Icon(Icons.calculate_outlined), selectedIcon: const Icon(Icons.calculate), label: t('nav_calc')),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: t('nav_recipes')),
          NavigationDestination(icon: const Icon(Icons.point_of_sale_outlined), selectedIcon: const Icon(Icons.point_of_sale), label: t('nav_sales')),
          NavigationDestination(icon: const Icon(Icons.more_horiz), label: t('nav_more')),
        ],
      ),
    );
  }
}
