import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BafangRideSyncApp extends Application.AppBase {

    // Set to true to feed static captured frames instead of live BLE.
    // Lets the Garmin Simulator show realistic data without a physical bike.
    // Flip back to false before sideloading on a real device.
    static const SIMULATE as Boolean = true;

    private static var _data as BafangData = new BafangData();

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new BafangRideSyncView()];
    }

    // Shared data accessor – called by both View and BleDelegate.
    static function getData() as BafangData {
        return _data;
    }
}
