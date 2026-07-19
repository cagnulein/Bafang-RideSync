# Garmin workout probe

This build can verify whether `Activity.getCurrentWorkoutStep()` is readable
from the Bafang RideSync data field during a native Garmin workout.

## Build

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
"$SDK/bin/monkeyc" \
  -f monkey.jungle \
  -o /tmp/BafangRideSync.prg \
  -y "$HOME/Documents/GitHub/QZCompanionGarmin/developer_key" \
  -d fr965 \
  -l 2
```

## Run in simulator

Open the Connect IQ simulator, then:

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
"$SDK/bin/monkeydo" /tmp/BafangRideSync.prg fr965
```

The app prints workout probe changes to the console:

```text
Workout probe state/type/rawLow/rawHigh/hrLow/hrHigh
```

State values:

- `0`: API unsupported on the selected device.
- `1`: API exists, but no workout is active.
- `2`: workout step was read.
- `3`: API or step parsing error.

For an HR target, Garmin/FIT may expose absolute bpm with `+100` offset. For
example, raw `230..250` is normalized and displayed as `HR 130-150`.

## Simulator workflow

In Connect IQ Simulator:

1. Use `Simulation > FIT Data` to enable simulated activity data or load a
   workout FIT file.
2. Use `Simulation > Activity Data` to start recording.
3. If a workout is active, use the `Workout Step` button to advance steps.

The data field shows the normalized workout HR range on the lower right when it
can read one. It also writes these FIT developer fields:

- `wstate`
- `wtype`
- `wlow`
- `whigh`
- `whrlow`
- `whrhigh`
