# ztyping

A reimplementation of [UTyping](https://tosk.jp/utyping/) in Zig, using [wgpu-native](https://github.com/gfx-rs/wgpu-native) for rendering

# Platforms

Active platform support
 - Linux x86_64 glibc (x86_64-linux-gnu)

Compiles, ran at one point
 - Linux x86_64 musl (x86_64-linux-musl)
 - [Windows x86_64](https://github.com/Beyley/ztyping/issues/1) (x86_64-windows-gnu)
 - [Windows i686](https://github.com/Beyley/ztyping/issues/1) (x86-windows-gnu)

Compiles, untested
 - MacOS x86_64 (x86_64-macos)
 - MacOS aarch64 (aarch64-macos)

# Compilation

## Setup the environment
Install the latest build of zig `0.11.x` from [`https://ziglang.org/`](https://ziglang.org/) (or your favourite package manager)

## Extras

### Linux host
TODO

### MacOS host
TODO

### Windows host
TODO

## Lets do it

### Debug build
`$ zig build`
### Release build
`$ zig build -Doptimize=ReleaseFast`

## Options, explained
`-Doptimize=X`  Sets the optimization settings for the compilation, possible options are:
 - Debug
 - ReleaseFast
 - ReleaseSmall
 - ReleaseSafe

`-Dwgpu_from_source=true/false` Whether to build wgpu-native from source or not, using the `wgpu-native` submodule, see [here](#compiling-wgpu-native-from-source) for info about setting up

`-Dtarget=X`    Sets the target machine of the compilation, possible options are listed [here](#platforms) in parentheses, below is a matrix of supported cross compilation targets, host on the top, target on the left

|     | Linux x86_64 glibc | Linux x86_64 musl | MacOS x86_64 | MacOS arm64 | Windows x86_64 |
| --- | --- | --- | --- | --- | --- |
|Linux x86_64 glibc | ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|Linux x86_64 musl | ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|MacOS x86_64 | ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|MacOS arm64 | ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|[Windows x86_64](https://github.com/Beyley/ztyping/issues/1)| ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|[Windows x86](https://github.com/Beyley/ztyping/issues/1)| ❌ | ❓ | ❓ | ❓ | ❓ |

### Notes
 - Native compilation *will* act differently than cross compilation, this table is specifically referencing cross compilation

✔️ = Tested working<br>
🚧 = In progress<br>
❌ = Broken<br>
❓ = Untested, but likely broken<br>
🟨 = Untested, but likely functional<br>

### Compilation Notes 
 - Native compilation of Linux 86_64 works

## Compiling wgpu-native from source

### Why?
Allows debug builds and rapid modifications of wgpu-native, without packaging a library yourself

### How?
Uses `cross` to setup a container for cross compilation of rust code, follow [their setup instructions](https://github.com/cross-rs/cross) beforehand

### From/to?

|     | Linux x86_64 glibc | Linux x86_64 musl | MacOS x86_64 | MacOS arm64 | Windows x86_64 |
| --- | --- | --- | --- | --- | --- |
|Linux x86_64 glibc| ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|Linux x86_64 musl| ❓ | ❓ | ❓ | ❓ | ❓ |
|MacOS x86_64| ❌ | ❌ | 🟨 | 🟨 | ❓ |
|MacOS arm64| ❌ | ❌ | 🟨 | 🟨 | ❓ |
|Windows x86_64| ✔️ | 🟨 | 🟨 | 🟨 | 🟨 |
|Windows x86| ❓ | ❓ | ❓ | ❓ | ❓ |
