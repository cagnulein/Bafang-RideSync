import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BafangRideSyncApp extends Application.AppBase {

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
