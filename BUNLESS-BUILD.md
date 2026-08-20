# Bunless build

This document describes the work required to build Bun without downloading or
executing a Bun binary as the build bootstrap runtime. It is a design and
inventory document, not an implementation plan for replacing the build system
with POSIX shell.

## Summary

The practical target is a Bunless bootstrap path that preserves the current
typed build graph and native toolchain. The Rust port makes Cargo the center of
the application build, but the final executable is still a Rust plus C/C++
link. Removing the bootstrap Bun is realistic; reducing the entire build to
Cargo alone is not.

A literal POSIX-sh port would be a much larger rewrite. The build system is
cross-platform, models toolchains and target triples, emits a dependency-aware
Ninja graph, and contains CI-specific orchestration. Shell would lose the type
boundaries and make the existing Windows, macOS, Linux, and cross-compilation
paths harder to maintain.

The existing build system is already partly prepared for this migration:
[`scripts/build/CLAUDE.md`](scripts/build/CLAUDE.md) documents running the
build under Node 24 with `--experimental-strip-types`. The remaining Bun
dependency is concentrated in package installation and code generation.

## Current build path

The static-artifact CI has two host paths, but both eventually execute the same
build script:

```text
macOS runner:  make macos-aarch64
Linux Docker: make arm64-static-musl / make x86_84-static-musl
                    |
                    v
        bun run build:release [--lto=on]
                    |
                    v
             scripts/build.ts
                    |
          configure + write build.ninja
                    |
                    v
                 ninja
```

The macOS target invokes Bun directly from [`Makefile`](Makefile). The Linux
Dockerfiles first download a pinned bootstrap Bun, verify its SHA-256, install
it as `/usr/local/bin/bun`, and then invoke the same command. This bootstrap Bun
is only the build tool; the Bun executable produced by the build is a separate
artifact.

### Phase 1: entry and argument routing

[`scripts/build.ts`](scripts/build.ts) is the CLI entry point. It:

- parses profile, feature, Ninja, and runtime arguments;
- handles Windows Visual Studio shell setup;
- optionally bypasses a proxy for Cargo downloads;
- calls `configure()`;
- runs Ninja locally or with CI annotations;
- optionally executes the newly built binary.

It is not itself a compiler driver. Its main job is to create and execute the
build graph.

### Phase 2: configure and graph emission

[`scripts/build/configure.ts`](scripts/build/configure.ts) resolves the host
and target toolchains, compiler/linker paths, SDKs, Rust configuration, build
profile, feature flags, source lists, and output directories. It then registers
rules and writes `build.ninja` plus `compile_commands.json`.

The generated graph is assembled by [`scripts/build/bun.ts`](scripts/build/bun.ts)
and contains:

1. dependency fetch, configure, and build edges;
2. code-generation edges;
3. Cargo compilation of `libbun_rust.a`;
4. C/C++ compilation and precompiled headers;
5. linking, stripping, and macOS `dsymutil` steps;
6. a small post-link smoke test.

Ninja owns incremental behavior. Inputs, outputs, depfiles, order-only
dependencies, `restat`, and pools are part of the contract. A replacement must
preserve those relationships; merely running the same commands serially is not
equivalent.

### What Cargo builds, and what it does not

The leaf crate [`src/bun_bin/Cargo.toml`](src/bun_bin/Cargo.toml) has
`crate-type = ["staticlib"]`. Cargo produces `libbun_rust.a`; it does not
produce the final `bun` executable. The static library occupies the link slot
where the old `bun-zig.o` artifact used to go.

The rest of the final link still includes:

- the JavaScriptCore bridge and generated bindings under `src/jsc/`, which
  currently contain hundreds of C++ translation units;
- C/C++ sources such as uSockets and SIMD/native shims;
- JavaScriptCore/WebKit libraries, either downloaded as prebuilts or built
  locally through WebKit's CMake build;
- vendored native dependencies such as BoringSSL, mimalloc, zlib/zstd,
  libarchive, and image/HTTP libraries;
- platform system libraries and the target's C runtime startup objects.

The C++ objects provide and consume the `extern "C"` boundary exported by the
Rust static library. The final executable is linked by the C++ driver and lld;
Cargo's static library is one input to that link, not a replacement for it.

### Phase 3: generated sources

[`scripts/build/codegen.ts`](scripts/build/codegen.ts) emits roughly twenty
code-generation rules and groups their outputs by consumer. The generated files
feed Rust `include!`s, C/C++ compilation, bundled JavaScript modules, and
link-time inputs.

The graph includes both configure-time and build-time generation:

- `buildOptionsRs` and JSON byte-classification tables are written while
  configuring;
- most generators run as Ninja edges;
- `bindgenv2` is invoked synchronously during configuration to discover its
  dynamic output set;
- package installs are represented by stamp files and implicit
  `node_modules/<package>/package.json` outputs.

## Where Bun is required today

| Boundary | Current behavior | Bunless replacement |
| --- | --- | --- |
| Build entry | `bun scripts/build.ts` | `node --experimental-strip-types scripts/build.ts`, or prebundle the build scripts for Node |
| Tool discovery | `configure.ts` requires `findBun()` and stores `cfg.bun` | Separate the JavaScript runtime from the package manager and codegen runtime |
| Generic codegen rule | Ninja runs about twenty scripts through `cfg.bun` | Run Node-compatible scripts through `cfg.jsRuntime` |
| Package installation | `bun install --frozen-lockfile` for the root and package-local dependencies | Choose a reproducible Node package-install contract, or provide preinstalled tool dependencies |
| Configure-time bindgen discovery | `bindgenv2/script.ts` runs through `cfg.bun` | Run it through the same Node JavaScript runtime after compatibility work |
| Bundling codegen | Several scripts use `Bun.build` and `Bun.Transpiler` | Invoke the already separate `esbuild` tool, or write a narrow compatibility adapter |
| File/process helpers | Codegen uses `Bun.file`, `Bun.write`, `Bun.spawnSync`, `Bun.Glob`, `Bun.sleep`, `Bun.hash`, and `Bun.inspect` | Replace each use with Node standard-library APIs or an explicit small helper |

The current split between `cfg.bun` and `cfg.jsRuntime` is important. The
`jsRuntime` path already supports Node for stream wrappers, fetch helpers, and
Ninja's self-reconfigure rule. `cfg.bun` remains because codegen still assumes
Bun APIs and because package installation is still hard-coded to Bun.

## Can the build become “Ninja and Cargo only”?

Not literally. Ninja and Cargo are orchestrators, not compilers or linkers. A
minimal static build still needs a native toolchain, at least:

- `clang++` or an equivalent C++ compiler;
- `lld` or another linker, plus `llvm-ar`/`ar` and `strip`;
- the Rust toolchain and Cargo;
- JavaScriptCore/WebKit libraries and headers;
- the vendored or prebuilt native dependency libraries;
- CMake when local WebKit or a nested native dependency is built.

For the static-artifact lane, where WebKit and the other large dependencies are
prebuilt, the *orchestration* could be reduced substantially. A possible end
state is:

```text
checked-in or generated build.ninja
        ├── codegen outputs already available, or native generators
        ├── cargo build -p bun_bin → libbun_rust.a
        ├── clang++ → src/jsc and generated C++ objects
        └── clang++/lld → bun
```

That removes Bun as a build runtime, but it does not remove C++, the linker, or
the native libraries. It also moves responsibility for source discovery,
target-specific flags, generated output declarations, and dependency paths
somewhere else. A hand-written Ninja file would be viable only for one pinned
platform/profile; the current TypeScript configurator exists because those
values vary across the supported matrix.

Therefore the useful reduction is:

```text
no Bun runtime
        + Node or another one-time codegen path
        + Ninja
        + Cargo
        + C/C++ compiler and linker
```

If generated sources and all native libraries are provisioned externally, the
one-time codegen path can disappear from the artifact-builder image. That is a
separate packaging decision from porting the repository's general-purpose
build system.

Representative Bun-specific codegen work includes:

- [`src/codegen/bundle-modules.ts`](src/codegen/bundle-modules.ts), which uses
  `Bun.Transpiler`, `Bun.Glob`, `Bun.build`, `Bun.file`, and `Bun.spawnSync`;
- [`src/codegen/bundle-functions.ts`](src/codegen/bundle-functions.ts), which
  uses `Bun.build`, `Bun.file`, and `Bun.write`;
- [`src/codegen/cppbind.ts`](src/codegen/cppbind.ts), which uses Bun file and
  subprocess APIs and can recursively invoke package installation;
- [`src/codegen/generate-jssink.ts`](src/codegen/generate-jssink.ts), which
  writes several generated C++ and Rust files through Bun APIs;
- [`src/codegen/create-hash-table.ts`](src/codegen/create-hash-table.ts),
  which reads input through `Bun.file`.

## Recommended migration shape

### 1. Define the bootstrap contract

Make the build distinguish three concepts:

- `jsRuntime`: the runtime used to execute TypeScript build and codegen
  scripts;
- `packageManager`: the command that materializes locked JavaScript tools;
- `esbuild`: the actual bundler executable, already resolved separately.

Do not silently fall back between package managers. The package manager must
have a documented lockfile, offline/cache behavior, and platform selection
contract.

### 2. Finish the Node build-entry path

Run `scripts/build.ts` under Node 24 and remove the unconditional
`findBun()` requirement from configure. Keep `cfg.jsRuntime` as the single
shell-ready command prefix for TypeScript subprocesses, including Ninja's
regeneration rule and configure-time `bindgenv2` discovery.

The first milestone should be `--configure-only` under Node. It must produce a
valid, deterministic `build.ninja` without executing any Bun-specific codegen.

### 3. Replace package installation deliberately

The root install currently provides `esbuild`; `@lezer/cpp` is used by
`cppbind`, and several package-local installs provide codegen inputs. Options
include:

- add and maintain a Node-compatible lockfile and use `npm ci`;
- use a separately provisioned, content-addressed tool cache;
- vendor only the small build-time packages that are required.

The choice affects reproducibility, network access, cache keys, and platform
support. It should be made before changing the Ninja `bun_install` rule.

### 4. Port codegen by dependency tier

Do not translate all codegen scripts at once.

1. Port file reads/writes, subprocesses, globbing, hashing, sleeping, and
   inspection to Node helpers.
2. Switch simple generators to `cfg.jsRuntime` and validate their output.
3. Audit `Bun.build` and `Bun.Transpiler` call sites separately. Their options
   and loader behavior are not automatically identical to the esbuild CLI.
4. Port `bindgenv2`'s configure-time output discovery.
5. Remove `cfg.bun` only after clean and incremental builds agree.

Generated output is the compatibility boundary. Each generator should be
validated for output contents, declared outputs, exit status, and incremental
mtime behavior—not merely that it runs.

### 5. Validate the full matrix

The Bunless path is complete only when it passes:

- clean and incremental debug/release builds;
- Linux x86_64 musl and Linux aarch64 musl static builds;
- macOS aarch64 builds;
- codegen-only and configure-only runs;
- removal of `bun` from `PATH` during configure, codegen, and compilation;
- the existing static-link, smoke-test, mimalloc, and archive checks.

The build output must be identical or intentionally explained relative to the
bootstrap-Bun path. Differences in generated JavaScript, platform replacement
values, source maps, or generated binding order are build correctness issues.

## Why not POSIX shell?

A shell rewrite would need to reproduce:

- typed profile and target resolution;
- compiler and SDK discovery across host/target combinations;
- Windows command quoting and Visual Studio setup;
- dependency variants and cache identity;
- Ninja rule and depfile emission;
- codegen output discovery;
- Rust/C++/LTO coordination;
- CI split modes, artifact handling, and diagnostics.

The build modules under `scripts/build/` total roughly fifteen thousand lines
of TypeScript. Rewriting that behavior in shell would create a second build
system, not remove a small bootstrap dependency. A Node-compatible TypeScript
build system keeps the existing contracts and limits the migration to the
actual Bun-specific edges.

## Definition of done

The migration is complete when:

1. configure and all Ninja codegen edges run with Node and the selected package
   manager;
2. `cfg.bun` and the Bun-specific install rule no longer exist in the build
   graph;
3. no build-time script reaches for a Bun-only API;
4. the build works with no `bun` executable available in `PATH`;
5. the static artifacts and their generated sources pass the existing CI
   checks on every supported lane.

Until then, CI should continue using the pinned Bun bootstrap. That path is
explicit, checksummed, and currently the smallest reliable way to build Bun.
