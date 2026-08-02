Goal:

> Implement a reproducible, Alpine-native Bun build that produces a truly statically linked musl binary, with no glibc, `gcompat`, dynamic loader, `libstdc++`, or `libgcc_s` runtime dependency.

Implement full static musl support for Bun in this checkout.

Investigate the existing build system, toolchain configuration, linker flags, native dependencies, and release/build documentation before changing anything. The target is a Bun executable built natively inside Alpine Linux using musl, without glibc or gcompat.

Requirements:

- Build inside an Alpine Linux container for the target architecture.
- Produce a genuinely static executable, not merely a dynamically linked musl binary.
- Do not require gcompat, glibc, libstdc++, libgcc_s, or any other runtime package beyond the base Alpine image.
- Do not use a wrapper script or launcher; the Bun executable itself must be static.
- Preserve the existing normal build path and platform behavior unless a change is required for static musl support.
- Avoid unrelated dependency upgrades or source changes.
- Document any upstream limitations, toolchain constraints, linker behavior, or required patches.

Add or update the appropriate build scripts, container files, CI configuration, and documentation. Make the build reproducible with pinned Alpine/toolchain inputs where practical.

Verification must include:

1. Build the binary inside Alpine without gcompat or glibc packages.
2. Confirm the output has no ELF interpreter (`PT_INTERP`) and is reported as statically linked by `file`/`readelf`.
3. Confirm `ldd` reports that it is not a dynamic executable.
4. Run the binary in a fresh minimal Alpine container containing only the binary and `/bin/sh`.
5. Verify at least:
   - `bun --version`
   - `bun -e 'console.log("ok")'`
   - compiling or running a small representative script
6. Confirm no runtime dependency on `libstdc++`, `libgcc_s`, glibc, or gcompat.
7. Compare the static binary’s size with the existing musl-dynamic build.
8. Add focused regression/build tests for the static-linking contract.

If fully static linking is impossible with the current toolchain, do not claim success. Identify the exact blocker, provide the smallest reproducible failure, and explain what code, dependency, or toolchain change would be required to remove it.

Finish with a concise summary of:
- files changed
- exact build command
- verification commands and results
- binary linkage evidence
- runtime dependency evidence
- size comparison
- remaining limitations
