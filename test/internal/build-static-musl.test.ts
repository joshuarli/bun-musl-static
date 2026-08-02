import { expect, test } from "bun:test";
import type { Config } from "../../scripts/build/config.ts";
import { computeFlags } from "../../scripts/build/flags.ts";

const cfg = (abi: "gnu" | "musl") =>
  ({
    linux: true,
    darwin: false,
    windows: false,
    freebsd: false,
    abi,
    arm64: false,
    x64: true,
    baseline: true,
    debug: false,
    release: true,
    asan: false,
    assertions: false,
    lto: false,
    crossLangLto: false,
    pgoGenerate: undefined,
    pgoUse: undefined,
    valgrind: false,
    staticSqlite: true,
    staticLibatomic: true,
    tinycc: true,
    fuzzilli: false,
    socketFaultInjection: false,
    unifiedSources: false,
    archiveDeps: false,
    timeTrace: false,
    canary: true,
    crossTarget: undefined,
    sysroot: undefined,
    ld: "/usr/bin/ld.lld",
    rustLld: undefined,
    buildDir: "/tmp/build",
    cwd: "/repo",
  }) as Config;

test("musl links the libc and C++ runtime statically", () => {
  const muslFlags = computeFlags(cfg("musl")).ldflags;

  expect(muslFlags).toContain("-static");
  expect(muslFlags).toContain("-static-libstdc++");
  expect(muslFlags).toContain("-static-libgcc");
  expect(muslFlags).not.toContain("-lstdc++");
  expect(muslFlags).not.toContain("-lgcc");
});

test("gnu keeps its existing static C++ runtime contract", () => {
  const gnuFlags = computeFlags(cfg("gnu")).ldflags;

  expect(gnuFlags).not.toContain("-static");
  expect(gnuFlags).toContain("-static-libstdc++");
  expect(gnuFlags).toContain("-static-libgcc");
});
