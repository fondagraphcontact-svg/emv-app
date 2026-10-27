import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'screens/assistant.dart';
import 'screens/faults.dart';
import 'screens/profile.dart';
import 'screens/vehicle.dart';
import 'screens/views.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/disclaimer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmvBootstrap());
}

class EmvBootstrap extends StatefulWidget {
  const EmvBootstrap({super.key});

  @override
  State<EmvBootstrap> createState() => _EmvBootstrapState();
}

class _EmvBootstrapState extends State<EmvBootstrap> {
  late final Future<AppState> _loading = _load();

  Future<AppState> _load() async {
    final results =
        await Future.wait([AppData.load(), SharedPreferences.getInstance()]);
    return AppState(results[0] as AppData, results[1] as SharedPreferences);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppState>(
        future: _loading,
        builder: (context, snap) {
          if (snap.hasData) return EmvApp(state: snap.data!);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: Scaffold(
              body: Center(
                child: snap.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Erreur de chargement des données :\n'
                            '${snap.error}'),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      );
}

class EmvApp extends StatelessWidget {
  final AppState state;

  const EmvApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          title: 'Electro Meca View',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const HomeShell(),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // The assistant loads its own data: build it on first visit only.
  bool _assistantOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (!state.disclaimerAccepted) {
        showDisclaimer(context,
            firstLaunch: true, onAccept: state.acceptDisclaimer);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _assistantOpened |= state.tab == AppTab.assistant;
    return Scaffold(
      body: IndexedStack(
        index: state.tab.index,
        children: [
          const VehicleScreen(),
          const ViewsScreen(),
          const FaultsScreen(),
          const ProfileScreen(),
          if (_assistantOpened)
            const AssistantScreen()
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tab.index,
        onDestinationSelected: (i) => state.selectTab(AppTab.values[i]),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.directions_car_outlined),
              selectedIcon: Icon(Icons.directions_car),
              label: 'Véhicule'),
          NavigationDestination(
              icon: Icon(Icons.view_in_ar_outlined),
              selectedIcon: Icon(Icons.view_in_ar),
              label: 'Vues'),
          NavigationDestination(
              icon: Icon(Icons.warning_amber_outlined),
              selectedIcon: Icon(Icons.warning_amber),
              label: 'Diagnostic'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
          NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Assistant'),
        ],
      ),
    );
  }
}
