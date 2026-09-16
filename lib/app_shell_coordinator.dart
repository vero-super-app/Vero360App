/// Keeps [MyApp]'s cached shell role in sync when navigation remounts Home.
class AppShellCoordinator {
  AppShellCoordinator._();

  static void Function()? _onGuestHome;
  static void Function(String role)? _onShellRole;

  static void register({
    required void Function() onGuestHome,
    void Function(String role)? onShellRole,
  }) {
    _onGuestHome = onGuestHome;
    _onShellRole = onShellRole;
  }

  static void markGuestHome() => _onGuestHome?.call();

  /// Notify MyApp that the visible shell is now customer / driver / merchant
  /// so a later `/users/me` sync does not remount the previous role.
  static void markShellRole(String role) => _onShellRole?.call(role);
}
