# Zview

An image viewer built using SDL3 that supports viewing individual images, image directories, and image archives (.zip, .cbz).

## Usage

Download [latest release](https://github.com/syeero7/zview/releases/latest)

### Linux

```bash
# make it executable
chmod +x ./zview

zview <path>
```

## Keybindings

```text
q      -  quit application
right  -  go to next image
left   -  go to previous image
l      -  rotate image clockwise
h      -  rotate image counter clockwise
z      -  zoom in
x      -  zoom out
```

## Build from Source

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
