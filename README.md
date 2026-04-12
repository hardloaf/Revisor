# Revisor / FilterSecurityCamera

FilterSecurityCamera is a small Swift command-line tool that uses Apple's Vision framework to detect humans, animals, or general objects in images. It is designed to run locally (no cloud uploads). For Mail integration the project provides a Revisor.scptd AppleScript bundle that contains the compiled AppleScript, a worker shell script, and the compiled FilterSecurityCamera binary.

Key points
- The repository supplies both a CLI (FilterSecurityCamera) and an AppleScript-based Mail integration (Revisor.scptd).
- `make` builds the FilterSecurityCamera binary.
- `make install` (recommended) compiles the AppleScript and installs a Revisor.scptd bundle to `~/Library/Application Scripts/com.apple.mail` containing the binary and helper scripts.

Installation

1. Build the tool:

    make

2. Install the script bundle (requires `osacompile` to produce a compiled script bundle; the Makefile falls back to a manual assembly when `osacompile` is unavailable):

    make install

This places `Revisor.scptd` in `~/Library/Application Scripts/com.apple.mail`. The compiled AppleScript will live at `Revisor.scptd/Contents/Resources/Scripts/main.scpt` and the bundled binary is located at `Revisor.scptd/Contents/Resources/FilterSecurityCamera`.

Usage

- Run the CLI directly:

    ./FilterSecurityCamera [options] <file-or-dir> [more...]

- Configure Mail: create a rule that runs the compiled `main.scpt` (the Mail rule should call the script bundle's `main.scpt`). The AppleScript locates the worker script inside the bundle and hands off message processing to it.

Options

- `-c`, `--confidence <value>`  Set minimum confidence threshold (0.0 to 1.0). Default: 0.6
- `-h`, `--human`              Enable dedicated human detection
- `-a`, `--animal`             Enable dedicated animal detection
- `-t`, `--train <folder>`     Save cropped detections into subfolders under this folder
- `-l`, `--list`               Print supported classification identifiers
- `-v`, `--version`            Print build/version information
- `--help`                     Show usage

Notes

- Exit codes: 0 if at least one image across inputs matched; 1 otherwise.
- The AppleScript locates resources using POSIX path of (path to resource workerName). For example:

  set workerPath to POSIX path of (path to resource workerName)

  This ensures the worker and binary are located inside the bundle and avoids hardcoded paths.

Development

- The AppleScript source is `FilterSecurityCamera.applescript` (compiled during install into the bundle).
- The worker script is `FilterSecurityCameraWorker.sh` and is installed into the bundle Resources.

License

MIT — see LICENSE

## Logging

Revisor writes debug logs exclusively to /var/log/revisor.log. If that file is missing or not writable, logging will be silent — create the file and adjust permissions to enable logging.

Logs include local-time timestamps and a component tag (e.g., [installer], [worker], [CLI], [AppleScript]).

The worker script logs every processing stage: attachment saving, number of files found, per-file tool invocation and its full output, detection results, message move actions, and cleanup.

If you prefer a different log location, adjust the scripts to set LOG_FILE accordingly.
