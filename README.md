# Zview

An image viewer built using SDL3 that supports viewing individual images, image directories, and image archives (.zip, .cbz).

## Usage

Download [latest release](https://github.com/syeero7/zview/releases/latest)

### Linux

Install dependencies

```bash
# fedora
sudo dnf install SDL3 SDL3_image

# arch
sudo pacman -S sdl3 sdl3_image

# debian/ubuntu
sudo apt install libsdl3 libsdl3-image
```

```bash
# make it executable
chmod +x ./zview

zview <path>
```

## Keybindings

| Keybind                    | Description                    |
| -------------------------- | ------------------------------ |
| `Q`                        | quit application               |
| `L`, `J`, `→`, `↓`         | view next image                |
| `H`, `K`, `←`, `↑`         | view previous image            |
| `Alt` + `L`, `J`, `→`, `↓` | rotate image clockwise         |
| `Alt` + `H`, `K`, `←`, `↑` | rotate image counter clockwise |
| `Z`                        | zoom in                        |
| `X`                        | zoom out                       |

## Build from Source

Install dependencies

```bash
# fedora
sudo dnf install SDL3-devel SDL3_image-devel

# arch
sudo pacman -S sdl3 sdl3_image

# debian/ubuntu
sudo apt install libsdl3-dev libsdl3-image-dev
```

Install [Zig](https://ziglang.org/intro/getting-started/) v0.17

```bash
# clone the repository
git clone https://github.com/syeero7/zview
cd zview

# native build
zig build -Doptimize=ReleaseFast

# build for multiple targets. check build.zig
zig build -Doptimize=ReleaseFast -Dmulti-targets
```
