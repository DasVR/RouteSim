# Contributing to RouteSim

Thank you for helping improve RouteSim. This project is focused on **realistic route-based location simulation** for iOS developer testing.

## What we welcome

- **Bug reports** — crashes, tunnel failures, playback drift, GTFS parse errors  
- **Simulation engine improvements** — `RoutePlayer`, `MovementProfile`, `DrivingDynamics`, `BusDwell`, `RouteGeometry`  
- **Route I/O** — GPX/KML/GeoJSON edge cases, GTFS feeds, persistence  
- **Documentation** — README, onboarding clarity, Life360 testing notes  
- **CI fixes** — `build_ipa.yml`, Xcode compatibility  

## What we generally do not accept

- Re-adding StikDebug bloat (JIT enabler UI, process inspector, script runner, multi-tab debugger)  
- Features aimed at evading safety, parental-control, or fraud-detection products  
- Moving or vendoring `StikDebug/idevice/` outside its current path  

## Before you open an issue

1. Search [existing issues](https://github.com/DasVR/RouteSim/issues).  
2. Confirm **iOS version**, **LocalDevVPN** status, and **pairing file** validity.  
3. For simulation bugs, note **mode**, **speed multiplier**, and whether **1× Drive** was used.

## Before you open a PR

1. Keep changes **focused** — one concern per PR.  
2. Match existing Swift style (SwiftUI, `@MainActor` for UI, serial queue for FFI).  
3. Do **not** rename the Xcode scheme/target (`StikDebug`) without a CI discussion.  
4. Do **not** move `StikDebug/idevice/libidevice_ffi.a`.  
5. Ensure the project still archives in CI (unsigned Debug IPA).

## Development setup

```bash
git clone https://github.com/DasVR/RouteSim.git
cd RouteSim
open StikDebug.xcodeproj
```

No Mac? Push to `main` and download **`RouteSim-Debug.ipa`** from GitHub Actions artifacts.

## Code of conduct

Be respectful. RouteSim is a developer tool — contributions that primarily enable abuse will be closed.

## Questions

Open a [Discussion](https://github.com/DasVR/RouteSim/discussions) or a [Feature Request issue](.github/ISSUE_TEMPLATE/feature_request.yml).
