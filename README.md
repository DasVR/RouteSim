<div align="center">

# RouteSim

**Realistic route-based location simulation for iOS developers**

Simulate Walk, Bike, Drive, Bus, or Custom movement along real routes — with steady 1 Hz GPS updates, derived speed & course, and a Life360-tuned Driving profile.

[![Build IPA](https://github.com/DasVR/RouteSim/actions/workflows/build_ipa.yml/badge.svg)](https://github.com/DasVR/RouteSim/actions/workflows/build_ipa.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![iOS 17.4+](https://img.shields.io/badge/iOS-17.4%2B-lightgrey)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-orange)](https://developer.apple.com/xcode/swiftui/)

[Getting Started](#getting-started) · [Features](#key-features) · [Build IPA](#building-from-source-no-mac-required) · [Architecture](#architecture-overview) · [Contributing](CONTRIBUTING.md)

</div>

---

## What is RouteSim?

**RouteSim** is a focused iOS app for **developer testing** of location-based services. It injects simulated GPS coordinates system-wide along a user-defined or imported route, with realistic movement profiles and playback controls.

RouteSim is a clean fork of [StikDebug](https://github.com/StephenDev0/StikDebug). All JIT, process inspection, scripting, and multi-tab debugger bloat has been removed. What remains is the debug tunnel (pairing file + LocalDevVPN + DVT location simulation) and a modern SwiftUI route editor built around a **`RoutePlayer`** engine.

> **Developer tool only.** RouteSim is intended for testing your own apps and services on devices you control. It is not a consumer spoofing product.

---

## Key Features

| Area | What you get |
|------|----------------|
| **Movement modes** | Walk · Bike · **Drive** · Bus · Custom — each with tuned speed, accel, braking, and jitter |
| **Life360 Drive mode** | Sustained 30–40 mph cruise, realistic ramp/brake, turn slowdown, strict **1 Hz** ticks at 1× |
| **Route editor** | MapKit map — tap waypoints, drag, delete, reorder; polyline overlay |
| **GPX import** | GPX, KML, GeoJSON, CSV, plain lat/lon text via Files app |
| **PSTA bus routes** | Runtime GTFS download (Pinellas Suncoast Transit Authority) — pick route + trip |
| **Playback** | Play / pause / scrub, 0.5×–10× multiplier, loop, live stats HUD (mph, course, distance, ETA) |
| **Persistence** | Save/load named routes as JSON; export GPX |
| **Onboarding** | Guided setup: pairing file → LocalDevVPN → Developer Mode → permissions |
| **Background** | Silent audio + location keep-alive so simulation survives screen lock |

---

## Why This Exists

Location-based apps (maps, fitness, family safety, transit, geofencing) are hard to test on a desk. Simulator location is app-scoped; real-world driving is slow and non-repeatable.

RouteSim lets you:

- Replay the **same route** with controlled speed and timing
- Validate **driving detection** heuristics (e.g. Life360) with GPS-realistic movement
- Test **bus dwell** and stop logic with GTFS-backed routes
- Iterate quickly without a Mac after initial sideload setup

---

## Screenshots

> Add captures to `docs/screenshots/` and uncomment the block below.

<!--
<div align="center">
  <img src="docs/screenshots/simulate-map.png" width="280" alt="Map route editor with playback HUD">
  <img src="docs/screenshots/modes.png" width="280" alt="Walk Bike Drive Bus mode chips">
  <img src="docs/screenshots/library.png" width="280" alt="Saved routes library">
  <img src="docs/screenshots/onboarding.png" width="280" alt="Onboarding pairing VPN steps">
  <img src="docs/screenshots/psta.png" width="280" alt="PSTA GTFS route browser">
  <img src="docs/screenshots/settings.png" width="280" alt="Settings tunnel and GTFS URL">
</div>
-->

**Suggested screenshots**

1. **Simulate tab** — map with waypoints, blue route polyline, mode chips, playback bar  
2. **Live stats HUD** — mph, course°, distance, progress while playing  
3. **Library** — saved routes list with mode icons  
4. **PSTA browser** — route list with bus colors / trip picker  
5. **Onboarding** — pairing file import step  
6. **Settings** — tunnel status, device IP, GTFS feed URL  

---

## Getting Started

### Requirements

| Requirement | Notes |
|-------------|--------|
| **iOS 17.4+** | Uses DVT/RSD location simulation (same family as StikDebug) |
| **Developer Mode** | Settings → Privacy & Security → Developer Mode |
| **Pairing file** | `.plist` / `.mobiledevicepairing` from a trusted Mac ([StikDebug pairing guide](https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md)) |
| **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** | Routes to device tunnel `10.7.0.1:49152` |
| **Sideload tool** | SideStore, AltStore, or similar |

### Install the IPA

1. Download **`RouteSim-Debug.ipa`** from the latest [GitHub Actions run](https://github.com/DasVR/RouteSim/actions/workflows/build_ipa.yml) (Artifacts section).
2. Sideload with SideStore or AltStore.
3. Trust the certificate: **Settings → General → VPN & Device Management**.

### First launch

1. Complete **onboarding** — import pairing file.  
2. Open **LocalDevVPN** and connect the VPN.  
3. Enable **Developer Mode** and reboot if prompted.  
4. RouteSim mounts the **Developer Disk Image (DDI)** automatically when the tunnel connects.  
5. On the **Simulate** tab, add waypoints and press **Play**.

---

## How to Use

### Create a route

- **Tap the map** to add waypoints (green = start, red = end).  
- Choose a **mode** chip: Walk / Bike / Drive / Bus / Custom.  
- **Import GPX** via the toolbar download icon.  
- **Save** from the ⋯ menu → Library.

### Playback

| Control | Behavior |
|---------|----------|
| **Play** | Prepares densified polyline, then ticks at **1 Hz** wall-clock |
| **Pause** | Holds last coordinate (4 s keep-alive) so iOS does not revert to real GPS |
| **Scrubber** | Jump along route by progress % |
| **Speed** | 0.5×–10× — use **1× for Life360 Drive testing** |
| **Loop** | Repeat route from start |

### Bus mode + PSTA

1. **Library → PSTA Routes** (or bus icon).  
2. Download/refreshes GTFS feed (URL configurable in Settings).  
3. Pick a route and trip → saved to Library with stop dwell metadata.

---

## Building from Source (No Mac Required)

You do **not** need a Mac to obtain a build. CI produces an unsigned Debug IPA on every push to `main`.

### GitHub Actions (recommended)

1. Fork or clone this repo.  
2. Push to `main` (or run **Actions → Build Debug IPA → Run workflow**).  
3. When the job finishes, download artifact **`RouteSim-Debug.ipa`**.  
4. Sideload as above.

The workflow uses Xcode **26.0.1** on `macos-latest`, scheme **`StikDebug`** (internal name kept for stability), and packages **`RouteSim-Debug.ipa`**.

### Local build (optional, requires Mac)

```bash
git clone https://github.com/DasVR/RouteSim.git
cd RouteSim
open StikDebug.xcodeproj
```

- Select the **StikDebug** scheme and your device.  
- Signing: automatic or ad-hoc; bundle ID is `com.stik.routesim`, display name **RouteSim**.  
- **Do not move** `StikDebug/idevice/` — `libidevice_ffi.a` is linked via build settings.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Features/          Simulate · Library · Onboarding · Settings │
│  Routes/            Models · RouteStore · GPX · GTFSService    │
│  Simulation/        RoutePlayer · MovementProfile · Geometry  │
│  Tunnel/            LocationSimulationBridge · TunnelManager │
│  idevice/           libidevice_ffi.a (prebuilt, do not move)   │
└─────────────────────────────────────────────────────────────┘
```

### RoutePlayer (core engine)

- **Odometer-based** interpolation along a densified polyline (not per-segment `Task.sleep`).  
- **`DispatchSourceTimer`** at ~**1 Hz** for stable derived speed/course.  
- **`DrivingDynamics`** — accel, brake, turn slowdown, jitter.  
- **`BusDwell`** — stop anchors and dwell windows from GTFS or defaults.  
- **`LocationSimulator`** — serial-queue wrapper over the C bridge.

### Derived speed & course (important)

The FFI (`location_simulation_set`) accepts **latitude and longitude only**. CoreLocation **derives** speed and course from the rate of change between successive fixes. RouteSim spaces updates accordingly — realism is **cadence-driven**, not a direct `CLLocation.speed` write.

---

## Life360 Testing Notes

RouteSim’s **Drive** profile is tuned for GPS-side realism:

| Setting | Value |
|---------|--------|
| Tick cadence | **1 Hz** at **1×** multiplier |
| Cruise | ~13.4 m/s (30 mph), floor ≥ 8 m/s (17 mph) |
| Accel / brake | 2.0 / 2.5 m/s² |
| Turn slowdown | Yes — bearing changes on densified polyline |

### Best practices

1. Use **Drive** mode, **1×** speed — not 2×+ (inflates derived speed).  
2. Use routes with **gentle turns** and enough length to sustain cruise speed.  
3. Keep **LocalDevVPN** connected and simulation **playing** (or paused with hold active).

### Limitations (read this)

> Life360 and similar apps also fuse **Core Motion** (accelerometer / activity). The DVT location service does **not** spoof motion coprocessor data — only GPS position. RouteSim optimizes everything on the GPS side; **driving detection is not guaranteed**.

Use RouteSim to test **your own** location logic and to understand GPS-derived behavior — not to mislead people or violate app terms of service.

---

## Repository Layout

```
RouteSim/
├── .github/workflows/build_ipa.yml   # CI → RouteSim-Debug.ipa
├── StikDebug/                        # App source (Xcode synced root)
│   ├── App/                          # RouteSimApp, RootView
│   ├── Tunnel/                       # Pairing, VPN tunnel, location bridge
│   ├── Simulation/                   # RoutePlayer engine
│   ├── Routes/                       # Persistence, GPX, GTFS
│   ├── Features/                     # SwiftUI screens
│   ├── Services/                     # Background keep-alive
│   └── idevice/                      # libidevice_ffi.a + headers (committed)
├── StikDebug.xcodeproj/              # Scheme name: StikDebug
├── StikDebugTests/
└── StikDebugUITests/
```

---

## Credits

| Project | Role |
|---------|------|
| **[StikDebug](https://github.com/StephenDev0/StikDebug)** by Stephen | Original debug tunnel, pairing, DDI, location FFI — fork base |
| **[idevice](https://github.com/jkcoxson/idevice)** | Rust/C FFI for RSD and `DtSimulateLocation` |
| **RouteSim fork** | Route engine, UI, GTFS, persistence, documentation |

---

## License & Disclaimer

- **RouteSim** documentation and new application code in this repository: **[MIT License](LICENSE)**.  
- **Upstream:** StikDebug and bundled `idevice` components are subject to their original licenses — see [NOTICE](NOTICE.md).

### Disclaimer

RouteSim is provided **for legitimate developer testing** on devices you own or are authorized to use. You are responsible for compliance with applicable law, Apple Developer policies, and third-party app terms. The authors do not encourage location misrepresentation, stalking, fraud, or circumvention of safety or parental-control products. **Use responsibly.**

---

<div align="center">
  <sub>Built for developers who need repeatable, realistic location testing.</sub>
</div>
