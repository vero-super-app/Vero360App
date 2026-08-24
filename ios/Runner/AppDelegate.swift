import Flutter
import UIKit
import FirebaseCore
import GoogleMaps
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required: creating a GoogleMap (Vero Ride) without this SIGABRTs on iOS.
    // Info.plist GMSApiKey alone is not enough — the SDK must be initialized here.
    var mapsKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if mapsKey.isEmpty {
      mapsKey = "AIzaSyBqvHbaR4EooNVrk9sgULwmIFJydKhERiE"
    }
    GMSServices.provideAPIKey(mapsKey)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // iOS push: show banners while app is foregrounded; register for APNs.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
#if canImport(FirebaseMessaging)
    // Forward APNs token to Firebase Messaging so FCM getToken() can succeed on iOS.
    Messaging.messaging().apnsToken = deviceToken
#endif
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
