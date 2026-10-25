# Right-Hand Drive Academy — v0.2.0

An **offline 3D learning-to-drive game project for Android** using Godot 4.3+ and procedural 3D car/road meshes. Intended for right-hand-drive regions (e.g. Bangladesh), with **left-side road traffic** and a steering wheel in the **right-hand seat**.

## New in v0.2 (requested features)

| Feature | What works |
|---|---|
| Realistic steering-wheel rotation | The steering-wheel joystick at bottom-right turns its visible spokes up to **450° left/right** (900° lock-to-lock). The matching 3D wheel spins around its tilted steering column. Road wheels turn and car steering is smoothed. |
| Side mirrors | Physical left/right door mirror housings on the 3D car, plus **two live, backward-facing mirror camera displays** in cockpit view. Low-resolution camera feeds are disabled in chase view to conserve phone performance. |
| Turn indicators | Touchable **◀ LEFT / RIGHT ▶ / HAZARD** buttons, flashing amber lamps front and back of car and blinking dashboard state. Tapping an active signal turns it off. |
| Handbrake | Touch **P BRAKE OFF/ON**. Can engage at very low speed, resists movement when applied. Lesson three requires a straight stop and an engaged handbrake. |
| Parking sensors | Selecting **R** activates rear obstacle proximity display. Detects traffic cars, a stationary car beside the bay, bollards and cones if behind the rear bumper. Beep rate increases as a detected obstacle gets closer. |
| Traffic vehicles | Three continuously circulating cars in the opposing lane, one crossing car that follows the traffic light phase and one stationary vehicle near the parking bay. Contact gives an in-game penalty. |
| Detailed dashboard | Live speedometer (km/h), approximate RPM, gear, fuel indicator, handbrake lamp, indicator status, parking sensor display and two moving physical instrument needles. |

## Existing lessons

1. Approach and stop at the white stop marking.
2. Cross the intersection **only when the signal is green**. Main street is left-hand traffic.
3. Park in the left-hand **blue parking bay**, stop straight, apply the **handbrake** to finish and save best score.

Arcade-style physics for training orientation only. **This is not a professional driver-training tool or a substitute for lessons with a certified instructor.** Reverse parking sensors use simplified geometry; they do not cover all hazards and are not equivalent to those on a real vehicle.

## Android touchscreen controls (landscape)

- **GAS** / **BRAKE**: hold to accelerate or brake.
- **DRAG TO STEER**: drag sideways on the large right-hand steering-wheel joystick; release to recenter.
- **GEAR D / GEAR R**: change only while stopped.
- **P BRAKE OFF / ON**: toggle manual handbrake.
- **◀ LEFT / RIGHT ▶ / HAZARD**: indicator switches, tap again to cancel.
- **COCKPIT / CHASE**: camera toggle. Live mirror feeds appear in cockpit.
- **RESET**: start the training sequence again.

## Desktop keyboard controls

| Key | Action |
|---|---|
| W / Up | Accelerate |
| S / Down / Space | Brake |
| A / D / Left / Right | Steer |
| E, Q | Drive, Reverse |
| H | Handbrake |
| Z, X, C | Left indicator, Right indicator, Hazards |
| V | Cockpit/chase camera |
| R | Restart |

## Export to Android APK

This archive contains **source code, not a compiled or tested APK**. The project is self-contained and has no external downloadable assets or network API calls. To export a sideloadable debug APK:

1. Unzip this folder to a working directory.
2. Import **project.godot** into **Godot 4.3+** with Android export support, or the Godot Android editor version that offers Android export.
3. Install matching Android export templates. On desktop, configure the Android SDK and signing credentials as described in the official Godot Android export documentation.
4. In **Project > Export**, select the supplied Android preset and export **RightHandDriveAcademy.apk** for local installation.
5. On phone, open the resulting APK and allow installation from that source if Android requests permission.

Official Godot instructions: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

## Quality and limitations

**Not compiled or run on a device in this environment.** API compatibility, performance and camera feed correctness still need device validation. Procedural car shapes and city are lightweight rather than photorealistic. AI vehicles use pre-set paths rather than general navigation. Mirror video feeds can be expensive on older phones; they only run in cockpit mode at 232×104 each. Physics, sensors and collision handling are simplified, with no rigid-body car damage, pedestrians, real road topology or driving-school certification. No internet permission is requested.

## Project files

- `main.tscn` — main scene.
- `scripts/main.gd` — 3D world, physics, traffic, instruments, mirrors, sensors, UI and lessons.
- `scripts/wheel.gd` — multitouch analog steering wheel.
- `project.godot` — Godot project.
- `export_presets.cfg` — Android export preset, package version 0.2.0.
- `assets/icon.png` — generated launcher icon.

No external art assets or asset licenses are required.
