import Toybox.Activity;
using Toybox.BluetoothLowEnergy as Ble;
import Toybox.FitContributor;
using Toybox.Graphics as Gfx;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
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
//   f5 dbgA  connected + parser error + RX packet size
//   f6 dbgB  rxCount low16 + validFrameCount low16
//   f7 dbgC  last frame src/dst/op/reg
class BafangRideSyncView extends WatchUi.DataField {

    private var _delegate as BafangBleDelegate?;

    // FIT contributor fields (nullable: createField may fail on older devices)
    private var _fR01a as FitContributor.Field?;
    private var _fR01b as FitContributor.Field?;
    private var _fR01c as FitContributor.Field?;
    private var _fR01d as FitContributor.Field?;
    private var _fR01e as FitContributor.Field?;
    private var _fDbgA as FitContributor.Field?;
    private var _fDbgB as FitContributor.Field?;
    private var _fDbgC as FitContributor.Field?;

    function initialize() {
        DataField.initialize();
        _initFitFields();
        _initBle();
    }

    // ── FIT contributor setup ─────────────────────────────────────────────

    private function _initFitFields() as Void {
        if (!(self has :createField)) { return; }
        var rec = {:mesgType => FitContributor.MESG_TYPE_RECORD};
        try {
            _fR01a = createField("r01a", 0, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01b = createField("r01b", 1, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01c = createField("r01c", 2, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01d = createField("r01d", 3, FitContributor.DATA_TYPE_UINT32, rec);
            _fR01e = createField("r01e", 4, FitContributor.DATA_TYPE_UINT32, rec);
            _fDbgA = createField("dbgA", 5, FitContributor.DATA_TYPE_UINT32, rec);
            _fDbgB = createField("dbgB", 6, FitContributor.DATA_TYPE_UINT32, rec);
            _fDbgC = createField("dbgC", 7, FitContributor.DATA_TYPE_UINT32, rec);
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

    function onLayout(dc as Gfx.Dc) as Void {
    }

    // Called once per second during activity recording.
    // Writes all packed raw FIT fields; display uses decoded values.
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        // Drive the GATT notify retry (Toybox.Timer not available in DataFields)
        if (_delegate != null) {
            (_delegate as BafangBleDelegate).tickRetry();
        }
        var d = BafangRideSyncApp.getData();
        _writeField(_fR01a, d.pack0601(0));
        _writeField(_fR01b, d.pack0601(4));
        _writeField(_fR01c, d.pack0601(8));
        _writeField(_fR01d, d.pack0601(12));
        _writeField(_fR01e, d.pack0601(16));
        _writeField(_fDbgA, d.diagStatusPacked());
        _writeField(_fDbgB, d.diagCountsPacked());
        _writeField(_fDbgC, d.lastFramePacked());
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

        // ── Debug screen while waiting for first telemetry ────────────────
        if (d.raw0601 == null) {
            _drawDebugScreen(dc);
            return;
        }

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

    // Shown instead of ride data until the first 06 01 telemetry frame arrives.
    // Lets you diagnose BLE init failures without needing to pull a FIT file.
    private function _drawDebugScreen(dc as Gfx.Dc) as Void {
        var w    = dc.getWidth();
        var h    = dc.getHeight();
        var d    = BafangRideSyncApp.getData();
        var tiny = Gfx.FONT_TINY;
        var lh   = dc.getFontHeight(tiny) + 2;
        var cx   = w / 2;
        var y    = h * 17 / 100;

        // State label (larger, coloured by connection)
        var stateColor = d.bleConnected ? Gfx.COLOR_GREEN : Gfx.COLOR_RED;
        dc.setColor(stateColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Gfx.FONT_SMALL, d.bleStatus, Gfx.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(Gfx.FONT_SMALL) + 4;

        // Init error code (0 = no error yet / still retrying)
        var errCode = d.lastParseError;
        if (errCode != 0) {
            dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, y, tiny, "Err: 0x" + errCode.format("%02X"),
                        Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(0x555555, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, y, tiny, "Err: none", Gfx.TEXT_JUSTIFY_CENTER);
        }
        y += lh;

        // GATT discovery progress (what was found / not found)
        dc.setColor(0x888888, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y, tiny, _gattStatusStr(errCode), Gfx.TEXT_JUSTIFY_CENTER);
        y += lh;

        // Retry counter while still attempting
        if (d.notifyRetryCount > 0) {
            dc.setColor(0x666666, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, y, tiny, "retry " + d.notifyRetryCount + "/10",
                        Gfx.TEXT_JUSTIFY_CENTER);
            y += lh;
        }

        // Descriptor probe results (updated on every _enableNotify() attempt)
        if (d.foundDescBitmask != 0 || errCode == 0xE4) {
            dc.setColor(0x777777, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, y, tiny, _descProbeStr(d.foundDescBitmask),
                        Gfx.TEXT_JUSTIFY_CENTER);
            y += lh;
        }

        // Actionable hint when CCCD is persistently missing (stale bonded GATT cache)
        if (errCode == 0xE4 && d.bleState == 14) {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, y, tiny, "Unpair EKD01-BF", Gfx.TEXT_JUSTIFY_CENTER);
            y += lh;
            dc.drawText(cx, y, tiny, "in watch settings", Gfx.TEXT_JUSTIFY_CENTER);
            y += lh;
        }

        // Raw packet counters
        dc.setColor(0x555555, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y, tiny,
                    "RX:" + d.rxCount + " OK:" + d.validFrameCount,
                    Gfx.TEXT_JUSTIFY_CENTER);
    }

    // Returns a short string showing which GATT objects were found/missing,
    // derived from the init error sub-code set by _enableNotify().
    //   + = found   - = not found   ? = not yet attempted
    private function _gattStatusStr(errCode as Number) as String {
        if (errCode == 0xE1) { return "SVC:- TX:? RX:? CCD:?"; }
        if (errCode == 0xE2) { return "SVC:+ TX:- RX:? CCD:?"; }
        if (errCode == 0xE3) { return "SVC:+ TX:+ RX:- CCD:?"; }
        if (errCode == 0xE4) { return "SVC:+ TX:+ RX:+ CCD:-"; }
        if (errCode == 0xE5) { return "SVC:+ TX:+ RX:+ CCD:+"; }
        return "SVC:? TX:? RX:? CCD:?";
    }

    // Decodes the descriptor probe bitmask from BafangData.foundDescBitmask:
    //   bit 0 = short CCCD (Ble.cccdUuid())
    //   bit 1 = long CCCD  (00002902-...-34fb)
    //   bit 2 = User Description (0x2901)
    private function _descProbeStr(bitmask as Number) as String {
        var s = (bitmask & 1) != 0 ? "+" : "-";
        var l = (bitmask & 2) != 0 ? "+" : "-";
        var u = (bitmask & 4) != 0 ? "+" : "-";
        return "CCDs:" + s + " CCDl:" + l + " Usr:" + u;
    }
}
