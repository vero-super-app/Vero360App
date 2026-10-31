enum Importance { none, min, low, defaultImportance, high, max }

enum Priority { min, low, defaultPriority, high, max }

enum AndroidNotificationCategory { call, message, event, status, transport, alarm }

enum NotificationVisibility { secret, private, public }

enum InterruptionLevel { passive, active, timeSensitive, critical }

enum NotificationResponseType {
  selectedNotification,
  selectedNotificationAction,
}

class AndroidNotificationChannel {
  const AndroidNotificationChannel(
    this.id,
    this.name, {
    this.description,
    this.importance = Importance.defaultImportance,
    this.playSound = true,
    this.enableVibration = true,
  });

  final String id;
  final String name;
  final String? description;
  final Importance importance;
  final bool playSound;
  final bool enableVibration;
}

class AndroidNotificationActionInput {
  const AndroidNotificationActionInput({
    this.label,
    this.allowFreeFormInput = true,
  });

  final String? label;
  final bool allowFreeFormInput;
}

class AndroidNotificationAction {
  const AndroidNotificationAction(
    this.id,
    this.title, {
    this.inputs = const <AndroidNotificationActionInput>[],
    this.showsUserInterface = false,
    this.cancelNotification = true,
  });

  final String id;
  final String title;
  final List<AndroidNotificationActionInput> inputs;
  final bool showsUserInterface;
  final bool cancelNotification;
}

class AndroidNotificationDetails {
  const AndroidNotificationDetails(
    this.channelId,
    this.channelName, {
    this.channelDescription,
    this.importance = Importance.defaultImportance,
    this.priority = Priority.defaultPriority,
    this.icon,
    this.category,
    this.actions,
    this.ongoing = false,
    this.autoCancel = true,
    this.fullScreenIntent = false,
    this.playSound = true,
    this.enableVibration = true,
    this.visibility,
    this.ticker,
    this.timeoutAfter,
    this.onlyAlertOnce = false,
    this.showProgress = false,
    this.maxProgress = 0,
    this.progress = 0,
    this.indeterminate = false,
  });

  final String channelId;
  final String channelName;
  final String? channelDescription;
  final Importance importance;
  final Priority priority;
  final String? icon;
  final AndroidNotificationCategory? category;
  final List<AndroidNotificationAction>? actions;
  final bool ongoing;
  final bool autoCancel;
  final bool fullScreenIntent;
  final bool playSound;
  final bool enableVibration;
  final NotificationVisibility? visibility;
  final String? ticker;
  final int? timeoutAfter;
  final bool onlyAlertOnce;
  final bool showProgress;
  final int maxProgress;
  final int progress;
  final bool indeterminate;
}

class DarwinNotificationDetails {
  const DarwinNotificationDetails({
    this.presentAlert = true,
    this.presentBadge = true,
    this.presentSound = true,
    this.interruptionLevel,
  });

  final bool presentAlert;
  final bool presentBadge;
  final bool presentSound;
  final InterruptionLevel? interruptionLevel;
}

class DarwinInitializationSettings {
  const DarwinInitializationSettings({
    this.requestAlertPermission = true,
    this.requestBadgePermission = true,
    this.requestSoundPermission = true,
  });

  final bool requestAlertPermission;
  final bool requestBadgePermission;
  final bool requestSoundPermission;
}

class AndroidInitializationSettings {
  const AndroidInitializationSettings(this.defaultIcon);
  final String defaultIcon;
}

class InitializationSettings {
  const InitializationSettings({this.android, this.iOS});
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;
}

class NotificationDetails {
  const NotificationDetails({this.android, this.iOS});
  final AndroidNotificationDetails? android;
  final DarwinNotificationDetails? iOS;
}

class NotificationResponse {
  const NotificationResponse({
    this.payload,
    this.actionId,
    this.input,
    this.notificationResponseType =
        NotificationResponseType.selectedNotification,
  });

  final String? payload;
  final String? actionId;
  final String? input;
  final NotificationResponseType notificationResponseType;
}

class NotificationAppLaunchDetails {
  const NotificationAppLaunchDetails({
    this.didNotificationLaunchApp = false,
    this.notificationResponse,
  });
  final bool didNotificationLaunchApp;
  final NotificationResponse? notificationResponse;
}

class AndroidFlutterLocalNotificationsPlugin {
  Future<void> createNotificationChannel(AndroidNotificationChannel channel) async {}
  Future<bool?> requestNotificationsPermission() async => false;
}

class IOSFlutterLocalNotificationsPlugin {
  Future<bool?> requestPermissions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async =>
      false;
}

class FlutterLocalNotificationsPlugin {
  Future<bool?> initialize(
    InitializationSettings settings, {
    dynamic onDidReceiveNotificationResponse,
    dynamic onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {}

  Future<void> cancel(int id, {String? tag}) async {}

  Future<void> cancelAll() async {}

  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async =>
      null;

  T? resolvePlatformSpecificImplementation<T>() => null;
}
