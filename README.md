# Universal Overlay Assistant

A lightweight macOS utility that grants large-language-model agents the ability to draw on-screen annotations and observe user interactions anywhere on the desktop.

## Features

- **Act Mode**: Draw on-screen annotations (highlight rectangles) at specified coordinates over any application
- **Observe Mode**: Monitor user clicks within specified regions and receive callbacks
- **Permission Handling**: Manages macOS privacy permissions (Accessibility, Screen Recording, Input Monitoring)
- **Menu Bar Integration**: Toggle between modes and check permission status via the menu bar
- **CLI Control**: Control the overlay assistant via the `overlayctl` command-line tool

## System Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon or Intel-based Mac
- Xcode 13.0 or later (for development)

## Installation

1. Download the latest release from the releases page
2. Move the application to your Applications folder
3. Launch the app
4. Grant the required permissions when prompted

## Usage

### Command-Line Interface

The `overlayctl` command-line tool can be used to control the overlay assistant:

```bash
# Draw a rectangle annotation at x=100, y=200 with width=300, height=100 in the Finder app
overlayctl act 100 200 300 100 com.apple.finder

# Monitor clicks in a region at x=500, y=600 with width=200, height=150
overlayctl observe 500 600 200 150

# Switch to Act mode
overlayctl mode act

# Switch to Observe mode
overlayctl mode observe
```

### Permissions

The application requires the following permissions:

- **Accessibility**: Required for drawing annotations
- **Screen Recording**: Required for capturing screen content
- **Input Monitoring**: Required for detecting clicks

These permissions can be granted in System Settings > Privacy & Security.

## Development

1. Clone the repository
2. Open `hopscotch.xcodeproj` in Xcode
3. Build and run the project

## License

Copyright © 2025. All rights reserved.

## Acknowledgments

- Based on PRD-v0.1.md 