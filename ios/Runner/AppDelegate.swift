import Flutter
import UIKit
import FirebaseCore
import GoogleMaps
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Maps + Firebase must be configured before any Flutter view uses them, but
    // both are local/synchronous (plist + API key). Never wait on the network
    // here — a stall before super.application leaves iPad on LaunchScreen forever
    // (App Store Guideline 2.1).
    var mapsKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if mapsKey.isEmpty {
      mapsKey = "AIzaSyBqvHbaR4EooNVrk9sgULwmIFJydKhERiE"
    }
    GMSServices.provideAPIKey(mapsKey)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // iOS push: show banners while app is foregrounded. Defer APNs registration
    // so it cannot block the first Flutter frame on iPadOS 27.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }

    return launched
  }

  // UIScene lifecycle: iOS/iPadOS 27 will not show a window for apps without a
  // scene manifest, so plugins register on the scene's implicit engine instead.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
