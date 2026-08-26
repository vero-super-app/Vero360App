/// Keeps [MyApp]'s cached shell role in sync when logout navigates to guest Home.
class AppShellCoordinator {
  AppShellCoordinator._();

  static void Function()? _onGuestHome;

  static void register({required void Function() onGuestHome}) {
    _onGuestHome = onGuestHome;
  }

  static void markGuestHome() => _onGuestHome?.call();
}
