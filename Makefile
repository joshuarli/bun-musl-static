BUN_LTO ?= on
DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=

.PHONY: macos-aarch64 arm64-static-musl x86_84-static-musl

macos-aarch64:
	@set -eu; \
	llvm_prefix="$$(brew --prefix llvm 2>/dev/null || true)"; \
	 lld_prefix="$$(brew --prefix lld 2>/dev/null || true)"; \
	 if test -n "$$llvm_prefix"; then \
		PATH="$$llvm_prefix/bin:$$lld_prefix/bin:$$PATH" \
		bun run build:release:lto; \
	 else \
		bun run build:release:lto; \
	 fi; \
	mkdir -p dist; \
	cp build/release-lto/bun dist/bun; \
	test -s dist/bun; \
	echo 'Wrote dist/bun'

arm64-static-musl:
	@set -eu; \
	image='bun-arm64-static-musl:local'; \
	container="bun-arm64-static-musl-$$$$"; \
	mkdir -p dist; \
	$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) --load --progress=plain \
		--platform=linux/arm64 \
		--build-arg LLVM_ARCH=aarch64 \
		--build-arg APK_ARCH=aarch64 \
		--build-arg BUN_ARCH=aarch64 \
		--build-arg BUN_LTO=$(BUN_LTO) \
		--build-arg BUN_GIT_SHA="$$(git rev-parse HEAD)" \
		--build-arg BUN_BOOTSTRAP_SHA256=576300ce33ff16ffcd455bf178c2f095f9df845c6cc3d0284ba1c96ca0e80473 \
		--file Dockerfile.arm64-static-musl \
		--tag "$$image" \
		.; \
	docker create --platform=linux/arm64 --name "$$container" "$$image" >/dev/null; \
	trap 'docker rm "$$container" >/dev/null 2>&1 || true' EXIT INT TERM; \
	docker cp "$$container:/usr/local/bin/bun" dist/bun; \
	test -s dist/bun; \
	docker run --rm --platform=linux/arm64 "$$image" --version; \
	echo 'Wrote dist/bun'

x86_84-static-musl:
	@set -eu; \
	image='bun-x86_84-static-musl:local'; \
	container="bun-x86_84-static-musl-$$$$"; \
	mkdir -p dist; \
	$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) --load --progress=plain \
		--platform=linux/amd64 \
		--build-arg LLVM_ARCH=x86_64 \
		--build-arg APK_ARCH=x86_64 \
		--build-arg BUN_ARCH=x64 \
		--build-arg BUN_LTO=$(BUN_LTO) \
		--build-arg BUN_GIT_SHA="$$(git rev-parse HEAD)" \
		--build-arg BUN_BOOTSTRAP_SHA256=83b5f12fd258dd8d4fdcaea65ede954366aa717dab399e20093ecab280d54e7a \
		--file Dockerfile.x86_84-static-musl \
		--tag "$$image" \
		.; \
	docker create --platform=linux/amd64 --name "$$container" "$$image" >/dev/null; \
	trap 'docker rm "$$container" >/dev/null 2>&1 || true' EXIT INT TERM; \
	docker cp "$$container:/usr/local/bin/bun" dist/bun; \
	test -s dist/bun; \
	docker run --rm --platform=linux/amd64 "$$image" --version; \
	echo 'Wrote dist/bun'
