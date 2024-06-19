# ffi-flang-zig

FFI between flang-new runtime and Zig

[LLVM/flang v18.1.7](https://github.com/llvm/llvm-project/tree/llvmorg-18.1.7/flang) files are included in this repository.

Inspired by [sourceryinstitute/ISO_Fortran_binding](https://github.com/sourceryinstitute/ISO_Fortran_binding). However, for LLVM-based only!

## Requires

- [Zig](https://ziglang.org/download) v0.13.0 or master
- [Flang-new](https://github.com/llvm/llvm-project/tree/llvmorg-18.1.7/flang)


## How to use

Build docker and run image:

```bash
$ docker build -t flang-zig -f .devcontainer/Dockerfile
$ docker run -it --rm -v $(pwd):/app -w /app flang-zig bash
```