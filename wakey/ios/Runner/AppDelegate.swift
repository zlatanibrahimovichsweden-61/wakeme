import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Maps key resolution order:
    //   1. Info.plist "MAPS_API_KEY" (populated from the MAPS_API_KEY build
    //      setting, which comes from ios/Flutter/Maps.xcconfig — written from
    //      the .env locally, or from a CI secret on Codemagic).
    //   2. An Xcode scheme env var, for ad-hoc local runs.
    let mapsKey =
      (Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String)
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? ProcessInfo.processInfo.environment["MAPS_API_KEY"]
        ?? ""
    GMSServices.provideAPIKey(mapsKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
