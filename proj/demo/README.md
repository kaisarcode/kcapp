# Demo

Demo is a small graphical application that opens a native WebView and checks
the bundled desktop kclib libraries.

## What it does

When started, Demo opens a window and requests the build version of every
bundled kclib except the WebView library that hosts the application. On
success, the page displays each version and a small HTTP byte-projection check:

```text
b64 version: <timestamp>
...
http request bytes: 61
All kcapp kclib bridge tests passed.
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
