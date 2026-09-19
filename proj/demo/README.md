# Demo

Demo is a graphical application that opens a native WebView and verifies the generated `redp2p` JavaScript bridge.

## What it does

When started, Demo opens a window showing a simple page titled "redp2p Typed Bridge Test". The page runs a series of `redp2p` API calls through the generated `NativeBridge.redp2p` JavaScript interface and displays the result.

The test sequence verifies:
- String parameter handling (`redp2p_is_valid_id`)
- Opaque handle creation and return (`redp2p_open`)
- Handle passing to subsequent calls (`redp2p_set_vip`, `redp2p_set_stream_faults`)
- Scalar argument handling
- Version query (`redp2p_version`)
- Handle release (`redp2p_close`)

On success, the page displays:
```
redp2p version: <timestamp>
NativeBridge loaded successfully.
```

On failure, it displays:
```
NativeBridge error: <message>
```

This demonstrates that the kcapp generated bridge works end-to-end: JavaScript → NativeBridge → Lua bridge → FFI → native redp2p library.

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

A native window will open and run the bridge verification automatically.

## Requirements

- Linux: GTK 3 and WebKitGTK
- Windows: WebView2 Evergreen Runtime
- macOS: Cocoa and WKWebView (WebView is built into the OS)

The application is self-contained and includes all required native libraries.