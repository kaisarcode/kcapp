# Demo

Demo is a small application that converts text to Base64.

## What it does

You provide a text value and Demo prints the Base64 version of that text.

For example:

```text
Hello
```

becomes:

```text
SGVsbG8=
```

## How to use it

Open a terminal in the application folder and run the application with the text you want to encode.

On Linux or macOS:

```sh
./demo "Hello"
```

On Windows:

```sh
demo.exe "Hello"
```

The encoded value is printed directly in the terminal:

```text
SGVsbG8=
```

You can replace `Hello` with any text you want to encode.

For example:

```sh
./demo "Hello world"
```

## If no text is provided

If you start Demo without providing any text, it encodes an empty value.
