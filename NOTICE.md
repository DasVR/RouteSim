# Third-Party Notices

RouteSim is a fork of **StikDebug** (https://github.com/StephenDev0/StikDebug).

## StikDebug

- **Copyright:** Stephen / StikDebug contributors  
- **License:** GNU Affero General Public License v3.0 (AGPL-3.0)  
- **Used for:** Debug tunnel, pairing file handling, DDI mounting, location simulation FFI integration  

Portions of the Tunnel layer and related infrastructure in this repository are derived from or based on StikDebug. If you redistribute modified versions of those portions, AGPL-3.0 obligations may apply to that combined work. See the upstream repository for the full AGPL-3.0 text.

## idevice

- **Project:** https://github.com/jkcoxson/idevice  
- **Bundled as:** `StikDebug/idevice/libidevice_ffi.a`, `idevice.h`, `module.modulemap`  
- **Purpose:** C FFI for Remote Service Discovery and `DtSimulateLocation`  

Review the idevice project license for terms governing the prebuilt static library.

## RouteSim-specific code

New modules added in this fork (including `Simulation/`, `Routes/`, `Features/`, and documentation) are released under the MIT License — see [LICENSE](LICENSE).
