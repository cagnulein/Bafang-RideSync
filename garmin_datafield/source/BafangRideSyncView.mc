import Toybox.Activity;
using Toybox.BluetoothLowEnergy as Ble;
import Toybox.FitContributor;
using Toybox.Graphics as Gfx;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// DataField view: draws decoded e-bike data on screen; logs ALL raw bytes
// from 06 01 and 06 09 frames as packed u32 custom FIT fields.
//
// 8 custom RECORD fields (packed little-endian u32):
//   f0 r01a  DATA[ 0.. 3] of frame 06 01
//   f1 r01b  DATA[ 4.. 7]         (PAS @byte1, battery% @byte3)
//   f2 r01c  DATA[ 8..11]         (speed u16LE /100 @bytes1-2)
//   f3 r01d  DATA[12..15]         (trip spans bytes 3 here and 0-2 of r01c)
//   f4 r01e  DATA[16..19]         (odo spans bytes 3 here and 0-2 of r01d)
//   f5 r09a  DATA[ 0.. 3] of frame 06 09  (tick counter u16LE @bytes0-1)
//   f6 r09b  DATA[ 4.. 7]         (wheel config u16LE @bytes0-1)
//   f7 r09c  DATA[ 8..11]         (more config)
class BafangRideSyncView extends WatchUi.DataField {

    private var _delegate as BafangBleDelegate?;

    // FIT contributor fields (nullable: createField may fail on older devices)
    private var _fR01a as FitContributor.Field?;
    private var _fR01b as FitContributor.Field?;
    private var _fR01c as FitContributor.Field?;
    private var _fR01d as FitContributor.Field?;
    private var _fR01e as FitContributor.Field?;
    private var _fR09a as FitContributor.Field?;
    private var _fR09b as FitContributor.Field?;
    private var _fR09c as FitContributor.Field?;

    function initialize() {
        DataField.initialize();
        _initFitFields();
        _initBle();
    }

    // ── FIT contributor setup ─────────────────────────────────────────────

    private function _initFitFields() as Void {
        if (!(FitContributor has :createField)) { return; }
        var rec = {:mesgType => FitContributor.MESG_TYPE_RECORD};
        try {
            _fR01a = FitContributor.createField("r01a", 0, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01b = FitContributor.createField("r01b", 1, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01c = FitContributor.createField("r01c", 2, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01d = FitContributor.createField("r01d", 3, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01e = FitContributor.createField("r01e", 4, FitContributor.DATA_TYPE_UINT32, rec);
            _fR09a = FitContributor.createField("r09a", 5, FitContributor.DATA_TYPE_UINT32, rec);
            _fR09b = FitContributor.createField("r09b", 6, FitContributor.DATA_TYPE_UINT32, rec);
            _fR09c = FitContributor.createField("r09c", 7, FitContributor.DATA_TYPE_UINT32, rec);
        } catch (ex instanceof Lang.Exception) {
            System.println("FIT createField error: " + ex.getErrorMessage());
        }
    }

    // ── BLE setup ─────────────────────────────────────────────────────────

    private function _initBle() as Void {
        if (BafangRideSyncApp.SIMULATE) {
            BafangRideSyncApp.getData().injectSimFrames();
            return;
        }
        if (!(Ble has :registerProfile)) {
            BafangRideSyncApp.getData().bleStatus = "N/A";
            return;
        }
        try {
            _delegate = new BafangBleDelegate();
            Ble.setDelegate(_delegate);
            (_delegate as BafangBleDelegate).startScan();
        } catch (ex instanceof Lang.Exception) {
            System.println("BLE init error: " + ex.getErrorMessage());
            BafangRideSyncApp.getData().bleStatus = "ERR";
        }
    }

    // ── DataField lifecycle ───────────────────────────────────────────────

    function onLayout(dc as Gfx.Dc) as Boolean {
        return true;
    }

    // Called once per second during activity recording.
    // Writes all packed raw FIT fields; display uses decoded values.
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        var d = BafangRideSyncApp.getData();
        _writeField(_fR01a, d.pack0601(0));
        _writeField(_fR01b, d.pack0601(4));
        _writeField(_fR01c, d.pack0601(8));
        _writeField(_fR01d, d.pack0601(12));
        _writeField(_fR01e, d.pack0601(16));
        _writeField(_fR09a, d.pack0609(0));
        _writeField(_fR09b, d.pack0609(4));
        _writeField(_fR09c, d.pack0609(8));
        return null;
    }

    private function _writeField(field as FitContributor.Field?,
                                  value as Number?) as Void {
        if (field != null && value != null) {
            (field as FitContributor.Field).setData(value);
        }
    }

    // ── Drawing ───────────────────────────────────────────────────────────

    function onUpdate(dc as Gfx.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var d = BafangRideSyncApp.getData();

        // Background
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        // ── Header bar ────────────────────────────────────────────────────
        var hdrH = h * 14 / 100;
        dc.setColor(0x222222, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, w, hdrH);
        dc.setColor(0x888888, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, 0, Gfx.FONT_TINY, "BAFANG", Gfx.TEXT_JUSTIFY_LEFT);
        var statusColor = d.bleConnected ? Gfx.COLOR_GREEN : Gfx.COLOR_RED;
        dc.setColor(statusColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w - 4, 0, Gfx.FONT_TINY, d.bleStatus, Gfx.TEXT_JUSTIFY_RIGHT);

        // ── Battery  |  PAS ──────────────────────────────────────────────
        var y1 = h * 16 / 100;
        var battStr = d.battery != null ? (d.battery.toString() + "%") : "--%";
        var pasStr  = d.pas     != null ? ("PAS " + d.pas.toString()) : "PAS-";
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, y1, Gfx.FONT_SMALL, battStr, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w - 4, y1, Gfx.FONT_SMALL, pasStr, Gfx.TEXT_JUSTIFY_RIGHT);

        // ── Speed (large) ─────────────────────────────────────────────────
        var y2 = h * 34 / 100;
        var spdStr = d.speedKmh != null ? d.speedKmh.format("%.1f") : "--.-";
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y2, Gfx.FONT_NUMBER_MEDIUM, spdStr,
                    Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x666666, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y2 + h * 19 / 100, Gfx.FONT_TINY, "km/h",
                    Gfx.TEXT_JUSTIFY_CENTER);

        // ── Trip ──────────────────────────────────────────────────────────
        var y3 = h * 67 / 100;
        var tripStr = "T: " + (d.tripKm != null
            ? d.tripKm.format("%.2f") + " km"
            : "--.- km");
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, y3, Gfx.FONT_TINY, tripStr, Gfx.TEXT_JUSTIFY_LEFT);

        // ── Odometer ──────────────────────────────────────────────────────
        var y4 = h * 82 / 100;
        var odoStr = "O: " + (d.odometerKm != null
            ? d.odometerKm.format("%.1f") + " km"
            : "---.- km");
        dc.setColor(0xaaaaaa, Gfx.COLOR_TRANSPARENT);
        dc.drawText(4, y4, Gfx.FONT_TINY, odoStr, Gfx.TEXT_JUSTIFY_LEFT);

        // ── Model label (bottom, very dim) ────────────────────────────────
        if (!d.model.equals("--")) {
            dc.setColor(0x444444, Gfx.COLOR_TRANSPARENT);
            dc.drawText(w / 2,
                        h - dc.getFontHeight(Gfx.FONT_TINY),
                        Gfx.FONT_TINY, d.model, Gfx.TEXT_JUSTIFY_CENTER);
        }
    }
}
