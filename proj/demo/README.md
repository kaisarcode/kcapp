# Demo

Demo is a small graphical application that opens a native WebView and displays
the build version of the bundled redp2p library.

## What it does

When started, Demo opens a window and requests the redp2p build version from its
local backend. On success, the page displays:

```text
redp2p version: <timestamp>
NativeBridge loaded successfully.
```

If the request fails, the page displays the reported error instead.

## How to use it

Build the application for your platform, then run the generated executable.

On Linux or macOS:

```sh
./demo
```

On Windows:

```sh
demo.exe
```

## Requirements

- Linux: GTK 3 and WebKitGTK
- Windows: WebView2 Evergreen Runtime
- macOS: Cocoa and WKWebView
