# Bake
A partial `GNU Make` reimplementation in Lua, built to automate building softwares on [OpenComputers](https://www.curseforge.com/minecraft/mc-mods/opencomputers)' OpenOS.
The current version has been tested on Lua 5.2 and Lua 5.3.

A good reference for `GNU Make` can be found [here](https://makefiletutorial.com/). This also describes additional features that may be added to Bake in the future.

# Supported features
- Macros/variables
- Automatic variables (`$@`, `$?`, and `$^`)
- Targets
- File dependencies (and `.PHONY`)
- Command silencing with `-s` and `@` prefix.
- Error handling with `-i` and `-` prefix.

# Differences compared to GNU Make
- Variable assignment with `=` behaves like the 'simply expanded' `:=` operator. Recursive assignment with `=` and operators `?=` and `+=` are not yet implemented.

# Installation
To install this on OpenOS, just copy `bake.lua` to `/usr/bin/`.
Alternatively, you can unzip this repository into your OpenOS installation, cd into the repository and run `bake install` *from within* OpenOS. :wink:

As a side note, the installation process will be more complicated on a real computer and not worth it.

# Usage
Just use it like you would use `make` but name your Makefiles `Bakefile`.
