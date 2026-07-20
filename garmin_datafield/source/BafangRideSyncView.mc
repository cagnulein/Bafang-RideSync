import Toybox.Activity;
using Toybox.BluetoothLowEnergy as Ble;
import Toybox.FitContributor;
using Toybox.Graphics as Gfx;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// DataField view: draws decoded e-bike data on screen and logs compact decoded
// e-bike telemetry as custom FIT record fields.
//
// Custom RECORD fields:
//   f0 ebatt    battery percentage
//   f1 epas     current PAS/assist level
//   f2 epasmax  advertised max PAS/assist level candidate
//   f3 espd     e-bike speed in km/h
//   f4 etrip    e-bike trip distance in km
//   f5 eodo     e-bike odometer in km
//   f6 etick    06 09 tick/counter candidate
//   f7 ewheel   wheel configuration candidate in mm
//   f8 dbg      parser/connection diagnostics
//   f9-f14 workout probe state/target fields
class BafangRideSyncView extends WatchUi.DataField {

    private var _delegate as BafangBleDelegate?;
    private var _lastWorkoutSignature as String = "";

    // FIT contributor fields (nullable: createField may fail on older devices)
    private var _fBatt as FitContributor.Field?;
    private var _fPas as FitContributor.Field?;
    private var _fPasMax as FitContributor.Field?;
    private var _fSpeed as FitContributor.Field?;
    private var _fTrip as FitContributor.Field?;
    private var _fOdo as FitContributor.Field?;
    private var _fTick as FitContributor.Field?;
    private var _fWheel as FitContributor.Field?;
    private var _fDbg as FitContributor.Field?;
    private var _fWorkoutState as FitContributor.Field?;
    private var _fWorkoutType as FitContributor.Field?;
    private var _fWorkoutLowRaw as FitContributor.Field?;
    private var _fWorkoutHighRaw as FitContributor.Field?;
    private var _fWorkoutHrLow as FitContributor.Field?;
    private var _fWorkoutHrHigh as FitContributor.Field?;

    function initialize() {
        DataField.initialize();
        _initFitFields();
        _initBle();
    }

    // ── FIT contributor setup ─────────────────────────────────────────────

    private function _initFitFields() as Void {
        if (!(self has :createField)) { return; }
        var rec = {:mesgType => FitContributor.MESG_TYPE_RECORD};
        var recPct = {:mesgType => FitContributor.MESG_TYPE_RECORD,
                      :units => "%"};
        var recKmh = {:mesgType => FitContributor.MESG_TYPE_RECORD,
                      :units => "km/h"};
        var recKm = {:mesgType => FitContributor.MESG_TYPE_RECORD,
                     :units => "km"};
        var recMm = {:mesgType => FitContributor.MESG_TYPE_RECORD,
                     :units => "mm"};
        try {
            _fBatt = createField("ebatt", 0, FitContributor.DATA_TYPE_UINT8, recPct);
            _fPas = createField("epas", 1, FitContributor.DATA_TYPE_UINT8, rec);
            _fPasMax = createField("epasmax", 2, FitContributor.DATA_TYPE_UINT8, rec);
            _fSpeed = createField("espd", 3, FitContributor.DATA_TYPE_FLOAT, recKmh);
            _fTrip = createField("etrip", 4, FitContributor.DATA_TYPE_FLOAT, recKm);
            _fOdo = createField("eodo", 5, FitContributor.DATA_TYPE_FLOAT, recKm);
            _fTick = createField("etick", 6, FitContributor.DATA_TYPE_UINT16, rec);
            _fWheel = createField("ewheel", 7, FitContributor.DATA_TYPE_UINT16, recMm);
            _fDbg = createField("dbg", 8, FitContributor.DATA_TYPE_UINT32, rec);
            _fWorkoutState = createField("wstate", 9, FitContributor.DATA_TYPE_UINT8, rec);
            _fWorkoutType = createField("wtype", 10, FitContributor.DATA_TYPE_UINT8, rec);
            _fWorkoutLowRaw = createField("wlow", 11, FitContributor.DATA_TYPE_UINT16, rec);
            _fWorkoutHighRaw = createField("whigh", 12, FitContributor.DATA_TYPE_UINT16, rec);
            _fWorkoutHrLow = createField("whrlow", 13, FitContributor.DATA_TYPE_UINT8, rec);
            _fWorkoutHrHigh = createField("whrhigh", 14, FitContributor.DATA_TYPE_UINT8, rec);
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
    // Writes compact decoded FIT fields; display uses the same decoded values.
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        var d = BafangRideSyncApp.getData();
        _probeWorkoutStep(d);
        _writeField(_fBatt, d.battery);
        _writeField(_fPas, d.pas);
        _writeField(_fPasMax, d.pasMax);
        _writeField(_fSpeed, d.speedKmh);
        _writeField(_fTrip, d.tripKm);
        _writeField(_fOdo, d.odometerKm);
        _writeField(_fTick, d.tickCounter);
        _writeField(_fWheel, d.wheelCfg);
        _writeField(_fDbg, d.diagStatusPacked());
        _writeField(_fWorkoutState, d.workoutState);
        _writeField(_fWorkoutType, d.workoutTargetType);
        _writeField(_fWorkoutLowRaw, d.workoutTargetLowRaw);
        _writeField(_fWorkoutHighRaw, d.workoutTargetHighRaw);
        _writeField(_fWorkoutHrLow, d.workoutHrLow);
        _writeField(_fWorkoutHrHigh, d.workoutHrHigh);
        return null;
    }

    private function _writeField(field as FitContributor.Field?,
                                  value as Numeric or Null) as Void {
        if (field != null && value != null) {
            (field as FitContributor.Field).setData(value);
        }
    }

    private function _probeWorkoutStep(d as BafangData) as Void {
        if (!(Activity has :getCurrentWorkoutStep)) {
            d.noteWorkoutUnsupported();
            _logWorkoutProbe(d);
            return;
        }

        try {
            var stepInfo = Activity.getCurrentWorkoutStep();
            if (stepInfo == null) {
                d.noteWorkoutMissing();
                _logWorkoutProbe(d);
                return;
            }
            if (!(stepInfo has :step) || stepInfo.step == null) {
                d.noteWorkoutError();
                _logWorkoutProbe(d);
                return;
            }

            var step = stepInfo.step;
            var targetStep = step;
            if (!(targetStep has :targetType)
                    && (step has :activeStep)
                    && step.activeStep != null) {
                targetStep = step.activeStep;
            }

            var targetType = null;
            var lowRaw = null;
            var highRaw = null;
            var durationType = null;
            var durationValue = null;

            if (targetStep has :targetType) {
                targetType = targetStep.targetType;
            }
            if (targetStep has :targetValueLow) {
                lowRaw = targetStep.targetValueLow;
            }
            if (targetStep has :targetValueHigh) {
                highRaw = targetStep.targetValueHigh;
            }
            if (targetStep has :durationType) {
                durationType = targetStep.durationType;
            }
            if (targetStep has :durationValue) {
                durationValue = targetStep.durationValue;
            }

            var isHeartRate = false;
            if (targetType != null
                    && (Activity has :WORKOUT_STEP_TARGET_HEART_RATE)
                    && targetType == Activity.WORKOUT_STEP_TARGET_HEART_RATE) {
                isHeartRate = true;
            }
            if (targetType != null
                    && (Activity has :WORKOUT_STEP_TARGET_HEART_RATE_LAP)
                    && targetType == Activity.WORKOUT_STEP_TARGET_HEART_RATE_LAP) {
                isHeartRate = true;
            }

            d.updateWorkoutTarget(targetType, lowRaw, highRaw,
                                  durationType, durationValue, isHeartRate);
            _logWorkoutProbe(d);
        } catch (ex instanceof Lang.Exception) {
            System.println("Workout probe error: " + ex.getErrorMessage());
            d.noteWorkoutError();
            _logWorkoutProbe(d);
        }
    }

    private function _logWorkoutProbe(d as BafangData) as Void {
        var sig = d.workoutState.toString() + "/"
                + _numString(d.workoutTargetType) + "/"
                + _numString(d.workoutTargetLowRaw) + "/"
                + _numString(d.workoutTargetHighRaw) + "/"
                + _numString(d.workoutHrLow) + "/"
                + _numString(d.workoutHrHigh);
        if (!sig.equals(_lastWorkoutSignature)) {
            _lastWorkoutSignature = sig;
            System.println("Workout probe " + sig);
        }
    }

    private function _numString(value as Number?) as String {
        return value == null ? "-" : (value as Number).toString();
    }

    // ── Drawing ───────────────────────────────────────────────────────────

    function onUpdate(dc as Gfx.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var d = BafangRideSyncApp.getData();

        // Background
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        // Round watches clip aggressively near the edges, so keep all text
        // inside a conservative center column.
        var cx = w / 2;

        // ── Header ────────────────────────────────────────────────────────
        dc.setColor(d.bleConnected ? Gfx.COLOR_GREEN : Gfx.COLOR_RED,
                    Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 9 / 100, Gfx.FONT_TINY,
                    d.bleStatus, Gfx.TEXT_JUSTIFY_CENTER);

        // ── Battery  |  PAS ───────────────────────────────────────────────
        var y1 = h * 21 / 100;
        var battStr = d.battery != null ? (d.battery.toString() + "%") : "--%";
        var pasStr  = d.pas     != null ? ("PAS " + d.pas.toString()) : "PAS --";
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w * 31 / 100, y1, Gfx.FONT_SMALL, battStr,
                    Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w * 69 / 100, y1, Gfx.FONT_SMALL, pasStr,
                    Gfx.TEXT_JUSTIFY_CENTER);

        // ── Speed (large) ─────────────────────────────────────────────────
        var y2 = h * 36 / 100;
        var spdStr = d.speedKmh != null ? d.speedKmh.format("%.1f") : "--.-";
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y2, Gfx.FONT_NUMBER_MEDIUM, spdStr,
                    Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x666666, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 57 / 100, Gfx.FONT_TINY, "km/h",
                    Gfx.TEXT_JUSTIFY_CENTER);

        // ── Trip ──────────────────────────────────────────────────────────
        var y3 = h * 68 / 100;
        var tripStr = "TRIP " + (d.tripKm != null
            ? d.tripKm.format("%.2f") + " km"
            : "--.- km");
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y3, Gfx.FONT_TINY, tripStr, Gfx.TEXT_JUSTIFY_CENTER);

        // ── Odometer ──────────────────────────────────────────────────────
        var y4 = h * 78 / 100;
        var odoStr = "ODO " + (d.odometerKm != null
            ? d.odometerKm.format("%.1f") + " km"
            : "---.- km");
        dc.setColor(0xaaaaaa, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y4, Gfx.FONT_TINY, odoStr, Gfx.TEXT_JUSTIFY_CENTER);

        var workoutStr = _bottomString(d);
        dc.setColor(d.workoutState == 2 ? Gfx.COLOR_GREEN : 0xaaaaaa,
                    Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 88 / 100, Gfx.FONT_TINY, workoutStr,
                    Gfx.TEXT_JUSTIFY_CENTER);
    }

    private function _bottomString(d as BafangData) as String {
        if (d.bleStatus.find("E:") != null || d.lastDescriptorStatus != 0) {
            return "T" + d.txDescriptorCount.toString()
                 + " R" + d.rxDescriptorCount.toString()
                 + " C" + d.cccdLocation.toString()
                 + " S" + d.lastDescriptorStatus.toString()
                 + " A" + d.cccdWriteAttempts.toString()
                 + " W" + d.lastTxWriteStatus.toString();
        }
        return _workoutString(d);
    }

    private function _workoutString(d as BafangData) as String {
        if (d.workoutState == 0) { return "W:N/A"; }
        if (d.workoutState == 1) { return "NO WKT"; }
        if (d.workoutState == 3) { return "W:ERR"; }
        if (d.workoutHrLow != null && d.workoutHrHigh != null) {
            return "HR " + d.workoutHrLow.toString()
                 + "-" + d.workoutHrHigh.toString();
        }
        return "T" + _numString(d.workoutTargetType)
             + " " + _numString(d.workoutTargetLowRaw)
             + "-" + _numString(d.workoutTargetHighRaw);
    }
}
