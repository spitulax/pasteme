<h1 align="center">Pasteme</h1>
<p align="center">A very simple program to quickly copy frequently used file or project template to the current directory.</p>

> [!WARNING]
> 🚧 This program is still in development 🚧

## Quick Start

- Build the executable

```console
$ make release
$ ./build/pasteme
```

- Put your files or project templates in this directory:

> - Linux, MacOS, *BSD: `$XDG_CONFIG_HOME/pasteme/` or `~/.config/pasteme/`
> - Windows: `%APPDATA%\pasteme\`

- Go to the directory you want to copy the file into and run the program from there.

## Caveat

Untested on Windows since I couldn't get odin compiler to work inside wine.
