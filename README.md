# LSFG-VK 2 ARM64 for AYN Odin 3

Self-contained Decky Loader plugin for **AYN Odin 3 running Armada/Fedora ARM64**.

This build packages a native AArch64 `lsfg-vk` Vulkan layer and adds live switching between:

- **1X** — native passthrough, frame generation disabled while the Vulkan layer stays loaded;
- **2X / 3X / 4X** — Lossless Scaling frame generation.

The plugin is based on the upstream `decky-lsfg-vk` project and the development 2.0 branch of `lsfg-vk`. It is an unofficial device-specific adaptation and is not supported by the upstream projects or the Lossless Scaling developers.

## Download

Download the ZIP and matching SHA-256 file from [GitHub Releases](https://github.com/razoomnik/lsfg-vk2-arm64-odin3/releases).

Every push to `main` builds and validates the current plugin, then publishes a uniquely tagged **pre-release** (`main-<run>-<commit>`). These automatic builds do not replace the historical stable release and have not necessarily been tested on a device. A manual run is also available under **Actions → Build and release Decky ZIP → Run workflow** (select `main`).

The archive in the repository's `releases/` directory is the historical v0.13.0 package. It is not the current auto-build; use the Release assets above.

Install it through:

```text
Decky → Settings → Developer → Install Plugin from Zip
```

## Launch option

```bash
/usr/libexec/armada/armada-game-launch ~/.local/bin/lsfg-vk2-arm64 %command%
```

The plugin includes a **Copy Launch Option** button.

## What is included

```text
plugin/     Complete Decky plugin payload, Python backend and built frontend bundle
engine/     Patched lsfg-vk 2.0 development source corresponding to the bundled ARM64 layer
patches/    Hot-1X patch against the original lsfg-vk development source
scripts/    Native Odin 3 build and repository packaging scripts
releases/   Ready Decky ZIP and SHA-256 checksum
LICENSES/   Upstream license texts
```

## Hot 1X implementation

The patched Vulkan layer accepts `multiplier = 1` and presents the application's original frame directly. The layer remains loaded, allowing the configuration watcher to recreate the frame-generation context when switching to 2X–4X without restarting the game.

When the game starts at 1X, the swapchain reserves enough image headroom for later live switching up to 4X.

## Build the ARM64 Vulkan layer on Odin 3

Copy the original `lsfg-vk-2.0.0-dev.zip`, the patch, and the build script to Odin 3. Then run:

```bash
sudo bootc usr-overlay

./scripts/build-hot1x-on-odin3.sh \
  ./lsfg-vk-2.0.0-dev.zip \
  ./patches/lsfg-vk-2.0-dev28-hot1x.patch
```

The script installs temporary build dependencies into the writable `/usr` overlay, compiles the AArch64 Vulkan layer, and installs it in the plugin's private user directory.

## Rebuild the Decky ZIP

```bash
./scripts/build-plugin-zip.sh
```

The resulting file is written to `releases/` with a portable SHA-256 file. The filename is derived from `plugin/package.json`. Set `OUT_DIR` to choose another output directory.

The workflow packages the checked-in ARM64 Vulkan binary and readable frontend bundle; it does not rebuild the Vulkan engine or install the plugin on your device.

## Source notes

- The Python backend source is included in full.
- The modified C++ Vulkan-layer source is included in full.
- The Decky frontend is included as the readable built `dist/index.js` bundle used by the release. The original TypeScript frontend project is maintained by the upstream Decky plugin project.

## Credits

- `decky-lsfg-vk` contributors for the Decky plugin base.
- `lsfg-vk` contributors for the Vulkan layer and backend.
- Lossless Scaling developers for the original frame-generation implementation.
- AYN Odin 3 / Armada testers who helped validate the ARM64 path.

## License

This repository contains components under multiple licenses:

- Decky plugin-derived code: BSD 3-Clause;
- patched `lsfg-vk` engine source and corresponding binary: GNU GPL v3;
- additional third-party notices retained in the plugin and source trees.

See `LICENSES/` and the license files inside `plugin/` and `engine/`.
