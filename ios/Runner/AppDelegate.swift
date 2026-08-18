import Flutter
import UIKit
import FirebaseCore
import GoogleMaps

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
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
