import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Hold a strong reference so the CBPeripheralManager stays alive for the app lifetime.
  private let gattPeripheral = GattPeripheral.shared

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
