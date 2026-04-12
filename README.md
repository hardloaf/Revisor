# classify_image

A lightweight Swift command-line tool that uses Apple's Vision framework to detect humans, animals, or general objects in images. Designed for local processing (no cloud uploads), it can also extract cropped examples for building training datasets.

## Features

- Human detection mode (VNDetectHumanRectangles)
- Animal detection mode (VNRecognizeAnimals)
- Generic image classification (VNClassifyImage)
- Recursive directory traversal: provide directories and the tool will deep-recurse image files
- Training export: crop detected objects and save into labeled folders with SHA-256 deduplication
- Configurable confidence threshold and simple output format for automation

## Installation

Build with the included Makefile (recommended):

    make

Or compile directly with Swift:

    swiftc classify_image.swift -o classify_image

## Usage

    ./classify_image [options] <file-or-dir> [more...]

Options:

- `-c`, `--confidence <value>`  Set minimum confidence threshold (0.0 to 1.0). Default: 0.6
- `-h`, `--human`              Enable dedicated human detection
- `-a`, `--animal`             Enable dedicated animal detection
- `-t`, `--train <folder>`     Save cropped detections into subfolders under this folder
- `-l`, `--list`               Print supported classification identifiers
- `-v`, `--version`            Print build/version information
- `--help`                     Show usage

Examples:

- Classify a single image:

      ./classify_image photo.jpg

- Recursively process a directory and export training crops:

      ./classify_image -a -t ./training_data /path/to/images

- Run human-only detection with a higher confidence threshold:

      ./classify_image -h -c 0.75 /path/to/camera_feed

## Output format

Each processed path prints either a list of `label:confidence` tokens, `NONE` (no detections above threshold), or `ERROR:<code>` for failures. Example:

    /path/to/img.jpg person:0.98 dog:0.87
    /path/to/blank.jpg NONE

Exit codes:

- `0` — at least one image (across all inputs) contained a detection meeting the configured threshold
- `1` — no detections met the threshold (or the set of inputs was empty)

## License

This project is released under the MIT License — see the bundled `LICENSE` file for details.
