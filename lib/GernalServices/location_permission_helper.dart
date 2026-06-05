import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Why location access could not be obtained.
enum LocationAccessIssue {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
}

/// Shared location permission checks, requests, and user guidance dialogs.
///
/// Caches the last known access state so callers can skip redundant system
/// checks, duplicate permission prompts, and repeated guidance dialogs.
class LocationPermissionHelper {
  LocationPermissionHelper._();

  static const Color primaryColor = Color(0xFFFF8A00);
  static const Color _orangeDark = Color(0xFFE07000);
  static const Color _orangeLight = Color(0xFFFFF0D9);

  static const Duration _grantedCacheTtl = Duration(minutes: 5);
  static const Duration _deniedCacheTtl = Duration(seconds: 30);

  static bool? _cachedGranted;
  static LocationAccessIssue? _cachedIssue;
  static DateTime? _cacheUpdatedAt;

  static bool _dialogVisible = false;
  static bool _userDeclinedPrompt = false;

  /// Whether the helper already knows location access is granted.
  static bool get isKnownGranted =>
      _cachedGranted == true && _isCacheFresh(granted: true);

  /// Clears cached permission state. Call when the app may have changed settings.
  static void invalidateCache() {
    _cachedGranted = null;
    _cachedIssue = null;
    _cacheUpdatedAt = null;
  }

  /// Call when the app returns to the foreground so settings changes are picked up.
  static void onAppResumed() {
    invalidateCache();
    _userDeclinedPrompt = false;
    _dialogVisible = false;
  }

  static bool _isCacheFresh({required bool granted}) {
    if (_cacheUpdatedAt == null || _cachedGranted == null) return false;
    final ttl = granted ? _grantedCacheTtl : _deniedCacheTtl;
    return DateTime.now().difference(_cacheUpdatedAt!) < ttl;
  }

  static void _updateCache({
    required bool granted,
    LocationAccessIssue? issue,
  }) {
    _cachedGranted = granted;
    _cachedIssue = issue;
    _cacheUpdatedAt = DateTime.now();
  }

  static Future<LocationAccessIssue?> _readAccessIssueFromSystem() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationAccessIssue.servicesDisabled;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return LocationAccessIssue.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationAccessIssue.permissionDenied;
    }
    return null;
  }

  /// Returns the current location access state without showing UI.
  static Future<LocationAccessIssue?> checkAccessIssue({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedGranted == false &&
        _cachedIssue != null &&
        _isCacheFresh(granted: false)) {
      return _cachedIssue;
    }

    if (!forceRefresh && isKnownGranted) {
      return null;
    }

    final issue = await _readAccessIssueFromSystem();
    _updateCache(granted: issue == null, issue: issue);
    return issue;
  }

  /// Returns `true` when location services and permission are available.
  static Future<bool> isAccessGranted({bool forceRefresh = false}) async {
    if (!forceRefresh && isKnownGranted) {
      return true;
    }

    if (!forceRefresh &&
        _cachedGranted == false &&
        _cachedIssue != null &&
        _isCacheFresh(granted: false)) {
      return false;
    }

    final issue = await checkAccessIssue(forceRefresh: forceRefresh);
    return issue == null;
  }

  /// Request permission when still allowed. Returns `true` when access is granted.
  static Future<bool> requestAccess() async {
    final issue = await checkAccessIssue(forceRefresh: true);
    if (issue == LocationAccessIssue.servicesDisabled) {
      _updateCache(granted: false, issue: issue);
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      _updateCache(
        granted: false,
        issue: LocationAccessIssue.permissionDeniedForever,
      );
      return false;
    }

    if (permission == LocationPermission.denied) {
      _updateCache(
        granted: false,
        issue: LocationAccessIssue.permissionDenied,
      );
      return false;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _updateCache(
        granted: false,
        issue: LocationAccessIssue.servicesDisabled,
      );
      return false;
    }

    _updateCache(granted: true, issue: null);
    return true;
  }

  /// Ensures location is available. Requests permission when possible and shows
  /// a guidance dialog when access is still blocked.
  static Future<bool> ensureLocationAccess(
    BuildContext context, {
    bool showDialogIfBlocked = true,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && await isAccessGranted()) {
      return true;
    }

    final issue = await checkAccessIssue(forceRefresh: forceRefresh);
    if (issue == null) return true;

    if (issue == LocationAccessIssue.permissionDenied) {
      final granted = await requestAccess();
      if (granted) return true;
      if (!context.mounted || !showDialogIfBlocked || _userDeclinedPrompt) {
        return false;
      }
      await showLocationNeededDialog(
        context,
        LocationAccessIssue.permissionDenied,
      );
      return false;
    }

    if (!context.mounted || !showDialogIfBlocked || _userDeclinedPrompt) {
      return false;
    }
    await showLocationNeededDialog(context, issue);
    return false;
  }

  /// Shows the guidance dialog once per blocked session when location is needed.
  static Future<void> promptIfBlocked(
    BuildContext context, {
    bool forceRefresh = false,
  }) async {
    if (_userDeclinedPrompt || _dialogVisible) return;
    if (!forceRefresh && await isAccessGranted()) return;

    final issue = await checkAccessIssue(forceRefresh: forceRefresh);
    if (issue == null || !context.mounted) return;

    await showLocationNeededDialog(context, issue);
  }

  /// Shows a dialog explaining why location is needed and how to enable it.
  static Future<void> showLocationNeededDialog(
    BuildContext context,
    LocationAccessIssue issue,
  ) async {
    if (_dialogVisible) return;
    _dialogVisible = true;

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final (title, message, primaryLabel, onPrimary) = switch (issue) {
      LocationAccessIssue.servicesDisabled => (
          'Turn on location',
          'Vero needs your device location to show nearby rides, track trips, '
              'and share your position with passengers. Please enable location '
              'services on your device.',
          'Open settings',
          Geolocator.openLocationSettings,
        ),
      LocationAccessIssue.permissionDenied => (
          'Location permission needed',
          'Vero needs access to your location to find rides, navigate, and keep '
              'your position up to date. Tap Allow when prompted.',
          'Allow location',
          requestAccess,
        ),
      LocationAccessIssue.permissionDeniedForever => (
          'Location permission needed',
          'Location access was denied. To use ride features, open app settings '
              'and allow Vero to access your location.',
          'Open settings',
          Geolocator.openAppSettings,
        ),
    };

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (dialogContext) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primaryColor.withValues(alpha: 0.18),
                            _orangeLight.withValues(alpha: 0.65),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.22),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 36,
                        color: _orangeDark,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: onSurface,
                            height: 1.15,
                          ) ??
                          TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: onSurface,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: onSurface.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w500,
                          ) ??
                          TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: onSurface.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _userDeclinedPrompt = true;
                              Navigator.of(dialogContext).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  onSurface.withValues(alpha: 0.85),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: BorderSide(
                                color: onSurface.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Text(
                              'Not now',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await onPrimary();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  primaryColor.withValues(alpha: 0.38),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              primaryLabel,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _dialogVisible = false;
    }
  }

  /// Returns a fresh GPS position only when permission and services are granted.
  static Future<Position?> getCurrentPositionIfGranted({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 10),
  }) async {
    if (!await isAccessGranted()) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeLimit,
        ),
      );
      _updateCache(granted: true, issue: null);
      return position;
    } catch (_) {
      invalidateCache();
      return null;
    }
  }
}
