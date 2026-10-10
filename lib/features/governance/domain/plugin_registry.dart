import '../../../domain/models/workspace_governance.dart';
import 'plugin_compatibility.dart';

enum PluginRegistrationState { pendingReview, enabled, disabled, blocked }

class PluginRegistration {
  final PluginManifest manifest;
  final PluginRegistrationState state;
  final Set<PluginPermission> approvedPermissions;
  final DateTime installedAt;
  final DateTime updatedAt;
  final List<String> errors;

  const PluginRegistration({
    required this.manifest,
    required this.state,
    required this.installedAt,
    required this.updatedAt,
    this.approvedPermissions = const {},
    this.errors = const [],
  });

  bool get isRunnable {
    if (state != PluginRegistrationState.enabled) return false;
    final requested = manifest.permissions.toSet();
    return approvedPermissions.length == requested.length &&
        approvedPermissions.containsAll(requested) &&
        requested.containsAll(approvedPermissions);
  }

  PluginRegistration copyWith({
    PluginRegistrationState? state,
    Set<PluginPermission>? approvedPermissions,
    DateTime? updatedAt,
    List<String>? errors,
  }) => PluginRegistration(
    manifest: manifest,
    state: state ?? this.state,
    approvedPermissions: approvedPermissions ?? this.approvedPermissions,
    installedAt: installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    errors: errors ?? this.errors,
  );

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'state': state.name,
    'approvedPermissions': approvedPermissions
        .map((permission) => permission.name)
        .toList(),
    'installedAt': installedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'errors': errors,
  };

  factory PluginRegistration.fromJson(Map<String, dynamic> json) {
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(json['manifest'] as Map),
    );
    return PluginRegistration(
      manifest: manifest,
      state: PluginRegistrationState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => PluginRegistrationState.pendingReview,
      ),
      approvedPermissions: _permissionsFromJson(json['approvedPermissions']),
      installedAt: DateTime.parse(json['installedAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  static Set<PluginPermission> _permissionsFromJson(Object? raw) {
    if (raw is! List) return const {};
    final permissions = <PluginPermission>{};
    for (final value in raw) {
      if (value is! String) {
        throw const FormatException(
          'Approved plugin permission must be a string.',
        );
      }
      final permission = PluginPermission.values
          .where((candidate) => candidate.name == value)
          .firstOrNull;
      if (permission == null) {
        throw FormatException('Unknown approved plugin permission: $value');
      }
      permissions.add(permission);
    }
    return permissions;
  }
}

class PluginRegistry {
  final DateTime Function() clock;
  final Map<String, PluginRegistration> _registrations = {};
  final Map<String, _PluginRuntime> _runtimes = {};

  PluginRegistry({
    Iterable<PluginRegistration> registrations = const [],
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    for (final registration in registrations) {
      _registrations[registration.manifest.id] = registration;
    }
  }

  List<PluginRegistration> get registrations =>
      List.unmodifiable(_registrations.values);

  PluginRegistration? find(String pluginId) => _registrations[pluginId];

  PluginRegistration register(PluginManifest manifest) {
    final compatibility = PluginCompatibilityKit.evaluate(manifest);
    final now = clock().toUtc();
    final state = compatibility.compatible && manifest.permissions.isEmpty
        ? PluginRegistrationState.enabled
        : compatibility.compatible
        ? PluginRegistrationState.pendingReview
        : PluginRegistrationState.blocked;
    final registration = PluginRegistration(
      manifest: manifest,
      state: state,
      installedAt: now,
      updatedAt: now,
      errors: compatibility.errors,
    );
    _registrations[manifest.id] = registration;
    _runtimes.remove(manifest.id);
    return registration;
  }

  PluginRegistration approve(
    String pluginId, {
    required Set<PluginPermission> permissions,
  }) {
    final registration = _require(pluginId);
    final compatibility = PluginCompatibilityKit.evaluate(
      registration.manifest,
    );
    if (!compatibility.compatible) {
      throw StateError('Plugin is incompatible and cannot be approved.');
    }
    final requested = registration.manifest.permissions.toSet();
    if (!requested.containsAll(permissions) ||
        !permissions.containsAll(requested)) {
      throw ArgumentError(
        'Permission review must approve exactly the requested permissions.',
      );
    }
    final updated = registration.copyWith(
      state: PluginRegistrationState.enabled,
      approvedPermissions: Set.unmodifiable(permissions),
      updatedAt: clock().toUtc(),
      errors: const [],
    );
    _registrations[pluginId] = updated;
    _runtimes.remove(pluginId);
    return updated;
  }

  PluginRegistration disable(String pluginId) =>
      _setState(pluginId, PluginRegistrationState.disabled);

  PluginRegistration enable(String pluginId) {
    final registration = _require(pluginId);
    final compatibility = PluginCompatibilityKit.evaluate(
      registration.manifest,
    );
    if (!compatibility.compatible ||
        registration.state == PluginRegistrationState.blocked) {
      throw StateError('Plugin is incompatible and cannot be enabled.');
    }
    final requested = registration.manifest.permissions.toSet();
    if (registration.approvedPermissions.length != requested.length ||
        !registration.approvedPermissions.containsAll(requested) ||
        !requested.containsAll(registration.approvedPermissions)) {
      throw StateError(
        'Plugin requires permission review before it can be enabled.',
      );
    }
    return _setState(pluginId, PluginRegistrationState.enabled);
  }

  bool uninstall(String pluginId) {
    _runtimes.remove(pluginId);
    return _registrations.remove(pluginId) != null;
  }

  bool admitCommand(String pluginId, PluginCommand command) {
    final registration = _registrations[pluginId];
    if (registration == null || !registration.isRunnable) return false;
    return _runtimeFor(pluginId).admitCommand(command);
  }

  bool subscribeEvent(String pluginId, PluginEventType event) {
    final registration = _registrations[pluginId];
    if (registration == null || !registration.isRunnable) return false;
    return _runtimeFor(pluginId).subscribeEvent(event);
  }

  bool reserveStorage(String pluginId, int bytes) {
    final registration = _registrations[pluginId];
    if (registration == null || !registration.isRunnable) return false;
    return _runtimeFor(pluginId).reserveStorage(bytes);
  }

  bool admitNetworkRequest(String pluginId) {
    final registration = _registrations[pluginId];
    if (registration == null || !registration.isRunnable) return false;
    return _runtimeFor(pluginId).admitNetworkRequest();
  }

  bool canReadEvent(String pluginId, PluginEventType event) {
    final registration = _registrations[pluginId];
    return registration != null &&
        registration.isRunnable &&
        registration.manifest.createSandbox().canReadEvent(event);
  }

  List<Map<String, dynamic>> toJson() =>
      registrations.map((registration) => registration.toJson()).toList();

  factory PluginRegistry.fromJson(
    List<dynamic> raw, {
    DateTime Function()? clock,
  }) => PluginRegistry(
    clock: clock,
    registrations: raw.whereType<Map>().map(
      (value) => PluginRegistration.fromJson(Map<String, dynamic>.from(value)),
    ),
  );

  _PluginRuntime _runtimeFor(String pluginId) =>
      _runtimes.putIfAbsent(pluginId, () {
        final registration = _require(pluginId);
        return _PluginRuntime(registration.manifest, clock: clock);
      });

  PluginRegistration _setState(String pluginId, PluginRegistrationState state) {
    final registration = _require(pluginId);
    final updated = registration.copyWith(
      state: state,
      updatedAt: clock().toUtc(),
    );
    _registrations[pluginId] = updated;
    return updated;
  }

  PluginRegistration _require(String pluginId) =>
      _registrations[pluginId] ??
      (throw StateError('Plugin is not registered: $pluginId'));
}

class _PluginRuntime {
  final PluginManifest manifest;
  final DateTime Function() clock;
  final PluginCommandGate commandGate;
  final Set<PluginEventType> _subscriptions = {};
  int _storageBytes = 0;
  int _networkRequests = 0;
  DateTime _networkWindowStarted;

  _PluginRuntime(this.manifest, {required this.clock})
    : commandGate = PluginCommandGate(manifest.createSandbox(), clock: clock),
      _networkWindowStarted = clock().toUtc();

  bool admitCommand(PluginCommand command) => commandGate.admit(command);

  bool subscribeEvent(PluginEventType event) {
    if (!manifest.createSandbox().canReadEvent(event)) return false;
    if (_subscriptions.contains(event)) return true;
    if (_subscriptions.length >= manifest.sandboxLimits.maxEventSubscriptions) {
      return false;
    }
    _subscriptions.add(event);
    return true;
  }

  bool reserveStorage(int bytes) {
    if (bytes < 0 || !manifest.requests(PluginPermission.storage)) return false;
    final next = _storageBytes + bytes;
    if (next > manifest.sandboxLimits.maxStorageBytes) return false;
    _storageBytes = next;
    return true;
  }

  bool admitNetworkRequest() {
    if (!manifest.requests(PluginPermission.network)) return false;
    final now = clock().toUtc();
    if (now.difference(_networkWindowStarted) >= const Duration(minutes: 1)) {
      _networkWindowStarted = now;
      _networkRequests = 0;
    }
    if (_networkRequests >=
        manifest.sandboxLimits.maxNetworkRequestsPerMinute) {
      return false;
    }
    _networkRequests++;
    return true;
  }
}
