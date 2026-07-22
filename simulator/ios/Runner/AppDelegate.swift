import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let hkReg = engineBridge.pluginRegistry.registrar(forPlugin: "HealthKitService") {
      HealthKitService.register(with: hkReg.messenger())
    }
    if #available(iOS 16.2, *) {
      if let laReg = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityService") {
        LiveActivityService.register(with: laReg.messenger())
      }
    }
  }
}
