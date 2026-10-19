# Desktop packaging

The Flutter frontend is shared across desktop platforms. The local FastAPI
backend is packaged separately on each operating system because PyInstaller
creates native executables.

## Windows

Run on Windows PowerShell:

```powershell
.\packaging\windows\build.ps1
```

## macOS

Run on macOS:

```bash
chmod +x packaging/build_unix.sh
./packaging/build_unix.sh macos
```

The macOS build requires Xcode and macOS desktop support in Flutter.

## Linux

Run on Linux:

```bash
chmod +x packaging/build_unix.sh
./packaging/build_unix.sh linux
```

The Linux build requires the Flutter Linux desktop dependencies and a working
Python 3 installation.

Build each target on that target's operating system. In particular, a macOS
application should be built on macOS and signed/notarized there when it will
be distributed to other Mac users.
