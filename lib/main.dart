import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mix/mix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/platform/desktop_window_manager.dart';
import 'app/legacy_project_migration_scheduler.dart';
import 'app/runtime_bootstrap.dart';
import 'app/supabase_bootstrap.dart';
import 'data/remote/supabase_service.dart';
import 'data/local/durable/durable_project_store.dart';
import 'data/local/durable/legacy_project_migration.dart';
import 'data/local/durable/project_session.dart';
import 'data/local/local_storage_service.dart';
import 'domain/models/collaboration.dart';
import 'features/ai/data/comfy_ui_bridge_manager.dart';
import 'app/theme.dart';
import 'app/theme_mode_provider.dart';
import 'app/localization/app_localizations.dart';
import 'app/accessibility_runtime.dart';
import 'features/governance/domain/accessibility_contract.dart';
import 'features/governance/state/accessibility_settings_provider.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/update_password_screen.dart';
import 'features/auth/state/auth_provider.dart';
import 'features/auth/state/auth_recovery.dart';
import 'features/canvas/presentation/guest_canvas_route_screen.dart';
import 'features/canvas/presentation/secure_share_screen.dart';
import 'features/canvas/state/autosave_controller.dart';
import 'features/collaboration/presentation/join_room_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/home/presentation/project_route_screen.dart';
import 'features/capture/domain/capture_canvas_handoff.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/meeting/presentation/pre_join_screen.dart';
import 'features/meeting/presentation/meeting_screen.dart';
import 'app/widgets/route_error_screen.dart';
import 'app/widgets/desktop_window_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  ErrorWidget.builder = (details) =>
      BootstrapFatalErrorSurface(details: details);
  if (defaultTargetPlatform == TargetPlatform.windows) {
    // Android and iOS use video_player; media_kit is only used for Windows playback.
    MediaKit.ensureInitialized();
  }
  JustAudioMediaKit.ensureInitialized();

  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  } else if (defaultTargetPlatform == TargetPlatform.windows) {
    await desktopWindowManager.ensureInitialized();
  }

  WidgetsBinding.instance.addObserver(_BridgeLifecycleObserver());

  // Keep one Riverpod-owned durable store for the app lifetime. The migration
  // and all project-scoped consumers read the same provider instance, so
  // startup cannot open and close a second Drift database for the same file.
  // Independent test containers can still override the provider with their own
  // in-memory store.
  final rootContainer = ProviderContainer();
  final durableStore = rootContainer.read(durableProjectStoreProvider);
  runApp(
    _RootProviderHost(
      container: rootContainer,
      child: const CreativeCanvasApp(),
    ),
  );

  // Legacy migration reads and validates every project. Keep it off the
  // startup isolate's first-frame path so the local library can render before
  // large or corrupt legacy records are processed. It reuses the app-owned
  // store instead of opening a second SQLite connection.
  scheduleLegacyProjectMigration(
    () => _migrateLegacyProjectStorage(durableStore),
  );
}

final class _RootProviderHost extends StatefulWidget {
  const _RootProviderHost({required this.container, required this.child});

  final ProviderContainer container;
  final Widget child;

  @override
  State<_RootProviderHost> createState() => _RootProviderHostState();
}

final class _RootProviderHostState extends State<_RootProviderHost> {
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.container,
    child: widget.child,
  );

  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }
}

Future<void> _migrateLegacyProjectStorage(DurableProjectStore store) async {
  try {
    await LegacyProjectMigration(
      store: store,
      legacy: LocalStorageService(),
    ).run();
  } catch (error) {
    debugPrint('[RuntimeBootstrap] Legacy project migration deferred: $error');
  }
}

final Future<void> _runtimeInitialization = Future<void>.value();

class _BridgeLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(shutdownComfyUiBridge());
    }
  }
}

bool _hasActiveSupabaseSession() {
  final bootstrapStatus = defaultSupabaseBootstrap.state.status;
  if (bootstrapStatus == SupabaseBootstrapStatus.deferred ||
      bootstrapStatus == SupabaseBootstrapStatus.initializing) {
    // Protected routes must not construct cloud repositories against a null
    // client. AuthScreen explicitly resumes bootstrap and returns to the
    // sanitized route once a persisted session is available.
    return false;
  }
  if (!isSupabaseInitialized()) return false;
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

String _authRedirectFor(GoRouterState state) {
  const safeQueryKeys = {
    'projectId',
    'meetingId',
    'section',
    'embed',
    'stage',
    'roomId',
    'role',
  };
  final safeQuery = <String, String>{};
  for (final key in safeQueryKeys) {
    final value = state.uri.queryParameters[key];
    if (value != null && value.isNotEmpty) safeQuery[key] = value;
  }
  final candidate = Uri(
    path: state.uri.path,
    queryParameters: safeQuery.isEmpty ? null : safeQuery,
  ).toString();
  final returnPath = AuthCallbackParser.safeLocalPath(candidate) ?? '/';
  return Uri(
    path: '/auth',
    queryParameters: returnPath == '/' ? null : {'returnTo': returnPath},
  ).toString();
}

final _routerRefresh = ValueNotifier<int>(0);

final _router = GoRouter(
  refreshListenable: _routerRefresh,
  initialLocation: '/',
  errorBuilder: buildRouteErrorScreen,
  routes: [
    GoRoute(
      path: '/',
      onExit: (context, state) async {
        final autosave = ProviderScope.containerOf(
          context,
        ).read(autosaveControllerProvider);
        final projectId = autosave.activeProjectId;
        if (projectId == null) return true;
        try {
          await autosave.flushAndDeactivateProject(projectId);
          return true;
        } catch (error) {
          debugPrint(
            '[Router] Guest canvas exit blocked by local save: $error',
          );
          return false;
        }
      },
      builder: (context, state) => const GuestCanvasRouteScreen(),
    ),
    GoRoute(
      path: '/library',
      redirect: (context, state) =>
          _hasActiveSupabaseSession() ? null : _authRedirectFor(state),
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/canvas/save',
      redirect: (context, state) =>
          _hasActiveSupabaseSession() ? null : _authRedirectFor(state),
      builder: (context, state) =>
          const GuestCanvasRouteScreen(saveAfterAuthentication: true),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/:section',
      builder: (context, state) =>
          SettingsScreen(section: state.pathParameters['section']),
    ),
    GoRoute(
      path: '/project/:projectId',
      redirect: (context, state) =>
          state.uri.queryParameters['role'] == null ||
              _hasActiveSupabaseSession()
          ? null
          : _authRedirectFor(state),
      onExit: (context, state) async {
        final autosave = ProviderScope.containerOf(
          context,
        ).read(autosaveControllerProvider);
        if (autosave.activeProjectId != state.pathParameters['projectId']) {
          return true;
        }
        try {
          await autosave.flush();
          return true;
        } catch (error) {
          debugPrint('[Router] Project exit blocked by durable save: $error');
          return false;
        }
      },
      builder: (context, state) => ProjectRouteScreen(
        projectId: state.pathParameters['projectId'] ?? '',
        captureHandoff: state.extra is CaptureCanvasHandoff
            ? state.extra as CaptureCanvasHandoff
            : null,
        collaborationRole: state.uri.queryParameters['role'] == null
            ? null
            : CollaborationRole.fromWire(state.uri.queryParameters['role']),
      ),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) =>
          AuthScreen(returnPath: state.uri.queryParameters['returnTo']),
    ),
    GoRoute(
      path: '/auth/update-password',
      builder: (context, state) => const UpdatePasswordScreen(),
    ),
    GoRoute(
      path: '/auth/callback-error',
      builder: (context, state) => const AuthCallbackErrorScreen(),
    ),
    GoRoute(
      path: '/join',
      redirect: (context, state) =>
          _hasActiveSupabaseSession() ? null : _authRedirectFor(state),
      builder: (context, state) =>
          JoinRoomScreen(initialRoomCode: state.uri.queryParameters['roomId']),
    ),
    GoRoute(
      path: '/meeting/:meetingId/stage',
      redirect: (context, state) =>
          _hasActiveSupabaseSession() ? null : _authRedirectFor(state),
      builder: (context, state) => MeetingScreen(
        meetingId: state.pathParameters['meetingId'] ?? '',
        projectId: state.uri.queryParameters['projectId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/meeting/:meetingId',
      redirect: (context, state) =>
          _hasActiveSupabaseSession() ? null : _authRedirectFor(state),
      builder: (context, state) => PreJoinScreen(
        meetingId: state.pathParameters['meetingId'] ?? '',
        projectId: state.uri.queryParameters['projectId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/share/:id',
      builder: (context, state) {
        final projectId = state.pathParameters['id'] ?? '';
        final token = state.uri.queryParameters['token'] ?? '';
        final embedRequested = state.uri.queryParameters['embed'] == '1';
        return SecureShareScreen(
          projectId: projectId,
          token: token,
          embedRequested: embedRequested,
          reader: ProviderScope.containerOf(
            context,
          ).read(sharedCanvasReaderProvider),
        );
      },
    ),
  ],
);

String? _lastHandledCallbackNavigation;

void _routeAuthCallback(AuthCallbackSnapshot snapshot) {
  if (snapshot.status == AuthCallbackStatus.idle ||
      snapshot.status == AuthCallbackStatus.processing) {
    return;
  }
  final key = [
    snapshot.eventId,
    snapshot.status.name,
    snapshot.kind.name,
    snapshot.returnPath ?? '',
    snapshot.message ?? '',
  ].join('|');
  if (_lastHandledCallbackNavigation == key) return;
  _lastHandledCallbackNavigation = key;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    switch (snapshot.status) {
      case AuthCallbackStatus.recovery:
        _router.go('/auth/update-password');
      case AuthCallbackStatus.error:
        _router.go('/auth/callback-error');
      case AuthCallbackStatus.signedIn:
        _router.go(snapshot.returnPath ?? '/');
      case AuthCallbackStatus.idle:
      case AuthCallbackStatus.processing:
        break;
    }
  });
}

class CreativeCanvasApp extends ConsumerWidget {
  const CreativeCanvasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final accessibility = ref.watch(accessibilitySettingsProvider);
    final callback = ref.watch(authCallbackCoordinatorProvider);
    ref.listen(authUserProvider, (_, _) => _routerRefresh.value++);
    _routeAuthCallback(callback);
    final accessibilityRuntime = AccessibilityRuntimeProfile.fromSettings(
      accessibility,
    );
    final supportedLocales = [
      ...FlutterQuillLocalizations.supportedLocales,
      ...CreativeStudioLocalizations.supportedLocales,
    ];
    return MaterialApp.router(
      title: 'Creative Canvas Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      locale: Locale(accessibility.locale),
      routerConfig: _router,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        CreativeStudioLocalizations.delegate,
      ],
      supportedLocales: supportedLocales,
      onGenerateTitle: (context) =>
          CreativeStudioLocalizations.of(context).appTitle,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MixScope.inherit(
          colors: AppMixTokens.colors(Theme.of(context).appTokens),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              highContrast:
                  mediaQuery.highContrast || accessibilityRuntime.highContrast,
              disableAnimations:
                  mediaQuery.disableAnimations ||
                  accessibilityRuntime.disableAnimations,
              textScaler: accessibilityRuntime.textScaler(
                mediaQuery.textScaler,
              ),
            ),
            child: Directionality(
              textDirection:
                  AccessibilityProfile(settings: accessibility).usesRtl
                  ? TextDirection.rtl
                  : Directionality.maybeOf(context) ?? TextDirection.ltr,
              child: Overlay.wrap(
                child: DesktopWindowTitleBar(
                  child: RuntimeBootstrap(
                    initialization: _runtimeInitialization,
                    bootstrap: defaultSupabaseBootstrap,
                    child: child ?? const BootstrapFatalErrorSurface(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
