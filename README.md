# fortty

A terminal emulator written in modern Fortran.

fortty aims to be a fully featured terminal with hardware acceleration, splits, configurable keybinds, and proper handling of terminal edge cases. It follows the architecture and solutions of existing terminals (ghostty, alacritty, wezterm) but implements everything from first principles in Fortran.

## Build

Requires gfortran 11+, GTK4, CMake 3.20+, and pkg-config.

macOS:
```bash
brew install gcc gtk4 cmake pkg-config
```

Arch Linux:
```bash
pacman -S gcc gtk4 cmake pkgconf
```

Debian/Ubuntu:
```bash
apt install gfortran libgtk-4-dev cmake pkg-config
```

Build and run:
```bash
make
./build/fortty
```

## License

MIT
