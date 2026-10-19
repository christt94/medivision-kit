# Windows standalone build

This package keeps the Flutter UI and FastAPI service local. The desktop app
starts `backend/medivision_backend.exe` automatically when that file is placed
next to the Flutter executable. See `packaging/README.md` for macOS and Linux
builds.

## Build prerequisites

- Windows 10 or later
- Flutter with Windows desktop support enabled
- Python 3.11
- Visual Studio with the Desktop development with C++ workload

From the project root in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\packaging\windows\build.ps1
```

The resulting release folder is:

```text
frontend\build\windows\x64\runner\Release
```

The build is offline-capable after packaging. Keep `IMAGING_MODEL=none` for a
credential-free installation. Add validated local model weights under the
future model directory only through a controlled model-update process.
