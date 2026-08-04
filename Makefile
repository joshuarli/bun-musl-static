.PHONY: bun arm64-static-musl-llvm22-alpine-native

BUN_LLVM_VERSION ?= 22.1.8

bun:
	@llvm_prefix="$$(brew --prefix llvm 2>/dev/null || true)"; \
	 lld_prefix="$$(brew --prefix lld 2>/dev/null || true)"; \
	 if test -n "$$llvm_prefix"; then \
		PATH="$$llvm_prefix/bin:$$lld_prefix/bin:$$PATH" \
		BUN_LLVM_VERSION="$(BUN_LLVM_VERSION)" \
		bun run build:release:lto; \
	 else \
		bun run build:release:lto; \
	 fi

# Vectorization warnings are from SIMDeâs `simde_vcvt_high_f32_f64` fallback loops. The target uses `armv8-a+crc` without FP16, selecting scalar fallback code marked with `#pragma clang loop vectorize(enable)`. LLVM 22 cannot vectorize those tiny private-vector conversion loops and reports warnings during ThinLTO; they are harmless optimization misses, not build failures.

arm64-static-musl-llvm22-alpine-native:
	@set -eu; \
	image='bun-arm64-static-musl-llvm22-alpine-native:local'; \
	container="bun-arm64-static-musl-llvm22-alpine-native-$$$$"; \
	mkdir -p dist; \
	docker build \
		--platform=linux/arm64 \
		--build-arg LLVM_ARCH=aarch64 \
		--build-arg APK_ARCH=aarch64 \
		--build-arg BUN_ARCH=aarch64 \
		--build-arg BUN_BOOTSTRAP_SHA256=5385e978107ce4934298d8d6afe9bfbb898683f6cc23e6753a0da60bc60c5b81 \
		--file Dockerfile.arm64-static-musl-llvm22-alpine-native \
		--tag "$$image" \
		.; \
	docker create --platform=linux/arm64 --name "$$container" "$$image" >/dev/null; \
	trap 'docker rm "$$container" >/dev/null 2>&1 || true' EXIT INT TERM; \
	docker cp "$$container:/usr/local/bin/bun" dist/bun; \
	test -s dist/bun; \
	echo 'Wrote dist/bun'
