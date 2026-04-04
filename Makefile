# Uya 项目根目录 Makefile
# 提供统一的构建和测试入口
#
# 若出现「没有规则可制作目标 install」：说明当前 Makefile 过旧，请用本仓库最新 Makefile
# 替换，或从上游同步后再执行：make install PREFIX=$HOME/.local

.PHONY: all from-c uya uya-hosted uya-std uya-nostdlib b b-hosted bench-compile-stats tests tests-hosted tests-uya outlibc c e clean check check-hosted backup backup-seed backup-all restore release install help

# 共享平台/工具链模型（可通过环境变量覆盖）
HOST_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed -e 's/darwin/macos/' -e 's/msys.*/windows/' -e 's/mingw.*/windows/' -e 's/cygwin.*/windows/')
HOST_ARCH ?= $(shell uname -m | sed -e 's/amd64/x86_64/' -e 's/aarch64/arm64/')
TARGET_OS ?= $(HOST_OS)
TARGET_ARCH ?= $(HOST_ARCH)
TARGET_TRIPLE ?=
RUNTIME_MODE ?= hosted
LINK_MODE ?= default
TOOLCHAIN ?= system
ZIG ?= /home/winger/zig/zig
CC ?= cc
ifeq ($(TOOLCHAIN),zig)
CC_DRIVER ?= $(ZIG) cc
else
CC_DRIVER ?= $(CC)
endif
CC_TARGET_FLAGS ?=

# 编译选项（可通过环境变量覆盖）
# 默认 -O2：加快自举编译器与 codegen 性能；调试可用 CFLAGS='-std=c99 -O0 -g ...' 覆盖
CFLAGS ?= -std=c99 -O2 -fno-builtin -Werror
LDFLAGS ?=

# 并行程序测试 worker 数（默认 CPU 核数；可覆盖：make tests UYA_TEST_JOBS=4）
UYA_TEST_JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)

# 安装路径（install 目标）
# 用法: make install
#       make install PREFIX=$$HOME/.local
#       make install BINDIR=/opt/bin
#       make install BINDIR=out            # 前缀布局：out/bin/uya + out/lib/（与 PREFIX 一致）
#       make install DESTDIR=/tmp/stage PREFIX=/usr   # 打包：安装到 /tmp/stage/usr/bin/uya
#       make install TESTSDIR=/path/tests             # 显式测试树目录（默认 前缀/tests）
# BINDIR 语义：
#   - 路径最后一段为 bin：视为「可执行目录」，如 /custom/bin → /custom/bin/uya、/custom/lib/
#   - 否则视为「安装前缀」，如 out、/opt/uya → 前缀/bin/uya、前缀/lib/（与 ~/.local 布局一致）
#       可显式覆盖 LIBDIR、DOCDIR；若与上述布局不一致，请设置环境变量 UYA_ROOT
PREFIX ?= out
BINDIR ?= $(PREFIX)/bin
_BINDIR_NORM := $(patsubst %/,%,$(BINDIR))
ifeq ($(notdir $(_BINDIR_NORM)),bin)
INSTALL_BINDIR := $(_BINDIR_NORM)
LIBDIR ?= $(patsubst %/,%,$(dir $(_BINDIR_NORM)))/lib
INSTALL_PREFIX := $(patsubst %/,%,$(dir $(_BINDIR_NORM)))
else
INSTALL_BINDIR := $(_BINDIR_NORM)/bin
LIBDIR ?= $(_BINDIR_NORM)/lib
INSTALL_PREFIX := $(_BINDIR_NORM)
endif
# 文档：与仓库根目录一致为 前缀/docs/*.md（uya_ai_prompt.md 及文中显式引用的规范文档）
DOCDIR ?= $(INSTALL_PREFIX)/docs
# 测试套件源码树：与仓库 tests/ 一致，安装到 前缀/tests/
TESTSDIR ?= $(INSTALL_PREFIX)/tests
# 打包时 DESTDIR 与相对 BINDIR（如 out）拼接须带 '/'，否则 /tmp/st + out → /tmp/stout
ifneq ($(strip $(DESTDIR)),)
INSTALL_DEST_ROOT := $(patsubst %/,%,$(DESTDIR))/
else
INSTALL_DEST_ROOT :=
endif

# 默认目标
all: help

# 空目标：用于捕获参数（避免 make 报错）
# 注意：uya 是真实目标，不能在这里声明
c e:
	@:

# 从 bin/uya.c 构建（零依赖）
from-c:
	@echo "=========================================="
	@echo "从 C99 代码构建编译器 (from-c)"
	@echo "=========================================="
	@if [ ! -f bin/uya.c ]; then \
		if [ -f backup/uya.c ]; then \
			echo "bin/uya.c 不存在，从备份恢复..."; \
			mkdir -p bin; \
			cp backup/uya.c bin/uya.c; \
		else \
			echo "错误: bin/uya.c 和 backup/uya.c 都不存在"; \
			exit 1; \
		fi \
	fi
	@echo "编译 bin/uya.c ..."
	@echo "CFLAGS: $(CFLAGS)"
	@echo "HOST_OS=$(HOST_OS) HOST_ARCH=$(HOST_ARCH)"
	@echo "TOOLCHAIN=$(TOOLCHAIN)"
	@echo "CC_DRIVER=$(CC_DRIVER)"
	@HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" \
		CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" \
		bash -c 'set -e; ulimit -s 32768 2>/dev/null || true; \
		if grep -qF "__attribute__((naked)) void _start(void)" bin/uya.c 2>/dev/null \
			&& [ "$$HOST_OS" = "macos" ]; then \
			echo "错误: backup/uya.c 为 Linux nostdlib（含 x86_64 Linux _start），无法在 macOS 上 make from-c。"; \
			echo "请从已构建的 hosted bin/uya 自举，或参见 docs/macos_hosted_smoke.md"; \
			exit 1; \
		fi; \
		if grep -qF "__attribute__((naked)) void _start(void)" bin/uya.c 2>/dev/null \
			&& [ "$$HOST_OS" = "linux" ] && [ "$$HOST_ARCH" = "x86_64" ]; then \
			echo "备份 C 含 nostdlib _start，使用 crti.o + uya.o + crtn.o 链接（避免与 Scrt1 _start 冲突）..."; \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS -fno-stack-protector -c bin/uya.c -o bin/.from_c.o; \
			CRTI=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crti.o); \
			CRTN=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crtn.o); \
			if [ ! -f "$$CRTI" ] || [ "$$CRTI" = "crti.o" ] || [ ! -f "$$CRTN" ] || [ "$$CRTN" = "crtn.o" ]; then \
				echo "错误: 当前工具链无法解析 crti.o/crtn.o，无法用 from-c 链接 nostdlib 版 uya.c"; exit 1; \
			fi; \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS -fno-stack-protector -no-pie -nostdlib -static \
				-o bin/uya "$$CRTI" bin/.from_c.o "$$CRTN" $$LDFLAGS; \
			rm -f bin/.from_c.o; \
		else \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS bin/uya.c -o bin/uya $$LDFLAGS; \
		fi'
	@echo ""
	@echo "✓ 编译器构建完成: bin/uya"
	@ls -la bin/uya

# 构建自举编译器（src），默认使用 --nostdlib（静态链接，零依赖）
uya:
	@echo "=========================================="
	@echo "构建自举编译器 (uya) --nostdlib"
	@echo "=========================================="
	@if [ ! -f bin/uya ]; then \
		echo "bin/uya 不存在，从备份构建..."; \
		$(MAKE) from-c; \
	fi
	@echo "使用 bin/uya 编译 src/ ..."
	@echo "TARGET_OS=$(TARGET_OS) TARGET_ARCH=$(TARGET_ARCH) TARGET_TRIPLE=$(TARGET_TRIPLE)"
	@bash -c 'ulimit -s 32768 && cd src && UYA_MULTI_FILE_C=1 UYA_SPLIT_C_DIR= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static CFLAGS="$(CFLAGS) -fno-stack-protector" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e --nostdlib'
	@echo ""
	@echo "更新 bin/uya.c（若存在单文件 src/build/uya.c）…"
	@if [ -f src/build/uya.c ]; then cp src/build/uya.c bin/uya.c && echo "✓ bin/uya.c 已更新"; else echo "（多文件 C：未生成 src/build/uya.c；单文件见 make backup-seed）"; fi
	@echo ""
	@echo "✓ 自举编译器构建完成: bin/uya（静态链接，零依赖）"
	@echo ""
	@echo "提示: 运行 'make b' 验证自举，通过后会自动备份"

# 构建自举编译器（hosted 版本）
uya-hosted:
	@echo "=========================================="
	@echo "构建自举编译器 (uya-hosted)"
	@echo "使用 hosted 链接路径"
	@echo "=========================================="
	@if [ ! -f bin/uya ]; then \
		echo "bin/uya 不存在，从备份构建..."; \
		$(MAKE) from-c; \
	fi
	@echo "使用 bin/uya 编译 src/ ..."
	@echo "TARGET_OS=$(TARGET_OS) TARGET_ARCH=$(TARGET_ARCH) TARGET_TRIPLE=$(TARGET_TRIPLE)"
	@bash -c 'ulimit -s 32768 && cd src && UYA_MULTI_FILE_C=1 UYA_SPLIT_C_DIR= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e'
	@echo ""
	@echo "更新 bin/uya.c（若存在单文件 src/build/uya.c）…"
	@if [ -f src/build/uya.c ]; then cp src/build/uya.c bin/uya.c && echo "✓ bin/uya.c 已更新"; else echo "（多文件 C：未生成 src/build/uya.c；单文件见 make backup-seed）"; fi
	@echo ""
	@echo "✓ 自举编译器构建完成: bin/uya（hosted）"
	@echo ""
	@echo "提示: 运行 'make b-hosted' 验证 hosted 自举"

# 构建自举编译器（标准库版本，用于调试）
uya-std: uya-hosted

# 构建自举编译器（--nostdlib 版本）- 别名
uya-nostdlib: uya

# 构建自举编译器（启用内存安全检查）
uya-safety:
	@echo "=========================================="
	@echo "构建自举编译器 (uya-safety)"
	@echo "启用内存安全检查 (--safety-proof)"
	@echo "=========================================="
	@if [ ! -f bin/uya ]; then \
		echo "bin/uya 不存在，从备份构建..."; \
		$(MAKE) from-c; \
	fi
	@bash -c 'ulimit -s 32768 && cd src && UYA_MULTI_FILE_C=1 UYA_SPLIT_C_DIR= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e --safety-proof'
	@echo ""
	@echo "✓ 自举编译器（内存安全版）构建完成: bin/uya"

# 自举验证：用自举编译器编译自身，验证输出一致性
b: uya
	@echo "=========================================="
	@echo "自举验证：编译器编译自身，验证输出一致性"
	@echo "=========================================="
	@bash -c 'ulimit -s 32768 && cd src && UYA_MULTI_FILE_C=1 UYA_SPLIT_C_DIR= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static CFLAGS="$(CFLAGS) -fno-stack-protector" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e -b --nostdlib'
	@echo ""
	@echo "✓ 自举验证完成"

# hosted 自举验证：用 hosted 编译器编译自身，验证输出一致性
b-hosted: uya-hosted
	@echo "=========================================="
	@echo "hosted 自举验证：编译器编译自身，验证输出一致性"
	@echo "=========================================="
	@bash -c 'ulimit -s 32768 && cd src && UYA_MULTI_FILE_C=1 UYA_SPLIT_C_DIR= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e -b'
	@echo ""
	@echo "✓ hosted 自举验证完成"

# 抓取编译器 CompileStats，便于对比 parse/check/codegen/total 耗时
bench-compile-stats:
	@bash scripts/bench_compile_stats.sh $(ARGS)

# 运行测试：默认使用 tests/run_programs_parallel.sh 并行测试（默认同 CPU 核数；可 UYA_TEST_JOBS= 或脚本 -j N）
# 默认 --hide-pass：不打印每条通过的 ✓，其余输出与直接跑脚本相同
# 用法: make tests [e] [其他参数]
# 示例: make tests e          # 最小输出（原 -e）
#       make tests test_file.uya
tests:
	@HAS_E=$$(echo "$(MAKECMDGOALS)" | grep -qE '\be\b' && echo "yes" || echo "no"); \
	OTHER_ARGS=$$(echo "$(MAKECMDGOALS)" | sed 's/tests//g' | sed 's/\be\b//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	echo "=========================================="; \
	echo "测试自举编译器 (uya)"; \
	echo "=========================================="; \
	$(MAKE) uya >/dev/null 2>&1; \
	if [ "$$HAS_E" = "yes" ]; then \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 -e $$OTHER_ARGS; \
	else \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 --hide-pass $$OTHER_ARGS; \
	fi; \
	TS=$$?; \
	echo ""; \
	if [ $$TS -ne 0 ]; then echo "✗ 测试失败（退出码 $$TS）"; exit $$TS; fi; \
	echo "✓ 测试完成"

# hosted 主测试集：为 Darwin/Windows 预留的普通链接测试主线
tests-hosted:
	@HAS_E=$$(echo "$(MAKECMDGOALS)" | grep -qE '\be\b' && echo "yes" || echo "no"); \
	OTHER_ARGS=$$(echo "$(MAKECMDGOALS)" | sed 's/tests-hosted//g' | sed 's/\be\b//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	echo "=========================================="; \
	echo "测试 hosted 编译器 (uya-hosted)"; \
	echo "=========================================="; \
	$(MAKE) uya-hosted >/dev/null 2>&1; \
	if [ "$$HAS_E" = "yes" ]; then \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99 -e $$OTHER_ARGS; \
	else \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99 --hide-pass $$OTHER_ARGS; \
	fi; \
	TS=$$?; \
	echo ""; \
	if [ $$TS -ne 0 ]; then echo "✗ hosted 测试失败（退出码 $$TS）"; exit $$TS; fi; \
	echo "✓ hosted 测试完成"

# 快捷目标：测试自举编译器（默认 tests/run_programs_parallel.sh 并行）
tests-uya:
	@HAS_E=$$(echo "$(MAKECMDGOALS)" | grep -qE '\be\b' && echo "yes" || echo "no"); \
	$(MAKE) uya >/dev/null 2>&1; \
	echo "=========================================="; \
	echo "测试自举编译器 (uya)"; \
	echo "=========================================="; \
	if [ "$$HAS_E" = "yes" ]; then \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 -e; \
	else \
		PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 --hide-pass; \
	fi; \
	TS=$$?; \
	if [ $$TS -ne 0 ]; then echo "✗ 测试失败（退出码 $$TS）"; exit $$TS; fi

# 输出标准库为 C 代码（使用自举编译器）
outlibc: uya
	@echo "=========================================="
	@echo "输出标准库为 C 代码 (outlibc)"
	@echo "使用自举编译器 (uya)"
	@echo "=========================================="
	@mkdir -p lib/build
	@echo "编译标准库文件..."
	@if [ -f bin/uya ]; then \
		COMPILER=bin/uya; \
	else \
		echo "错误: 找不到自举编译器，请先运行 'make uya'"; \
		exit 1; \
	fi; \
	echo "使用编译器: $$COMPILER"; \
	echo ""; \
	LIB_FILES=$$(find lib/libc/ -name "*.uya" -type f | sort); \
	if [ -z "$$LIB_FILES" ]; then \
		echo "错误: 未找到标准库文件 (lib/libc/*.uya)"; \
		exit 1; \
	fi; \
	echo "找到的标准库文件:"; \
	echo "$$LIB_FILES" | sed 's/^/  /'; \
	echo ""; \
	echo "生成 C 代码到 lib/build/libuya.c..."; \
	$$COMPILER --c99 $$LIB_FILES -o lib/build/libuya.c; \
	if [ $$? -eq 0 ]; then \
		echo ""; \
		echo "✓ 标准库 C 代码已生成: lib/build/libuya.c"; \
		FILE_SIZE=$$(du -h lib/build/libuya.c 2>/dev/null | cut -f1 || echo "未知"); \
		echo "  文件大小: $$FILE_SIZE"; \
		echo "  使用编译器: 自举编译器 (uya)"; \
	else \
		echo ""; \
		echo "✗ 生成失败"; \
		exit 1; \
	fi

# 清理构建产物
clean:
	@echo "清理构建产物..."
	@rm -rf bin
	@rm -rf src/build
	@rm -rf tests/programs/build
	@rm -rf lib/build
	@echo "✓ 清理完成"

# 备份 bin/uya.c（依赖自举验证和测试通过）
check: uya
	@echo "=========================================="
	@echo "运行测试验证..."
	@echo "=========================================="
	@PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" \
		HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" \
		TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" \
		TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" \
		RUNTIME_MODE=nostdlib LINK_MODE=static \
		./tests/run_programs_parallel.sh --uya --c99 --hide-pass > /tmp/make_check_output.txt 2>&1; \
	TEST_EXIT=$$?; \
	rm -f /tmp/uya_test_summary.txt; \
	echo ""; \
	echo "验证证明优化..."; \
	if ./tests/verify_proof_optimization.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗|证明优化" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ 证明优化验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证默认顶层函数发射..."; \
	if ./tests/verify_function_reachability_codegen.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ 默认顶层函数发射验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证 SIMD @vector.select C 按需生成..."; \
	if ./tests/verify_simd_select_c_emit.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ SIMD select C 按需生成验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证切片形参 C99 按值与调用约定..."; \
	if ./tests/verify_slice_param_c99_emit.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ 切片形参 C99 验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证 @syscall C99（Linux AArch64 / ARM32 交叉）..."; \
	if ZIG="$(ZIG)" ./tests/verify_syscall_c99_cross.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ @syscall C99 交叉目标验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证 SIMD C99（ARM NEON 片段交叉编译）..."; \
	if ZIG="$(ZIG)" ./tests/verify_simd_c99_neon.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ SIMD C99 NEON 验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证 benchmarks/http_bench.uya C99..."; \
	if ./tests/verify_http_bench_compile.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ http_bench C99 验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "验证 benchmarks/http_bench_async_epoll.uya C99..."; \
	if ./tests/verify_http_bench_async_epoll_compile.sh > /tmp/verify_out.txt 2>&1; then \
		grep -E "✓|✗" /tmp/verify_out.txt || cat /tmp/verify_out.txt; \
		VERIFY_EXIT=0; \
	else \
		cat /tmp/verify_out.txt; \
		VERIFY_EXIT=1; \
	fi; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ http_bench_async_epoll C99 验证失败"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "=========================================="; \
	echo "测试结果："; \
	echo "=========================================="; \
	if [ $$TEST_EXIT -ne 0 ]; then \
		echo "测试执行失败（退出码: $$TEST_EXIT）"; \
		grep -E "FAIL:|❌|失败:|编译失败|链接失败|未计入" /tmp/make_check_output.txt | tail -40 || true; \
		echo "--- 日志尾部（便于定位）---"; \
		tail -60 /tmp/make_check_output.txt; \
		rm -f /tmp/make_check_output.txt /tmp/verify_out.txt; \
		exit 1; \
	fi; \
	if [ -f /tmp/uya_test_summary.txt ]; then \
		cat /tmp/uya_test_summary.txt; \
		rm -f /tmp/uya_test_summary.txt; \
	else \
		grep -E "总计|通过|失败" /tmp/make_check_output.txt | tail -5; \
	fi; \
	rm -f /tmp/make_check_output.txt /tmp/verify_out.txt; \
	echo ""; \
	echo "✓ 验证通过（自举 + 测试 + 证明优化 + 默认顶层函数发射 + SIMD select C + 切片形参 C99 + @syscall C99 + SIMD NEON + http_bench C99 + http_bench_async_epoll C99）"

# hosted 验证：普通链接自举 + 主测试 + 证明优化
check-hosted: b-hosted
	@echo "=========================================="
	@echo "运行 hosted 测试验证..."
	@echo "=========================================="
	@PARALLEL_JOBS="$(UYA_TEST_JOBS)" UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99; \
	TEST_EXIT=$$?; \
	if [ $$TEST_EXIT -ne 0 ]; then \
		echo ""; \
		echo "✗ hosted 测试失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "验证证明优化..."
	@./tests/verify_proof_optimization.sh; \
	VERIFY_EXIT=$$?; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ 证明优化验证失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "验证默认顶层函数发射..."
	@./tests/verify_function_reachability_codegen.sh; \
	VERIFY_EXIT=$$?; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ 默认顶层函数发射验证失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "验证 SIMD @vector.select C 按需生成..."
	@./tests/verify_simd_select_c_emit.sh; \
	VERIFY_EXIT=$$?; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ SIMD select C 按需生成验证失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "验证 @syscall C99（Linux AArch64 / ARM32 交叉）..."
	@ZIG="$(ZIG)" ./tests/verify_syscall_c99_cross.sh; \
	VERIFY_EXIT=$$?; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ @syscall C99 交叉目标验证失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "验证 SIMD C99（ARM NEON 片段交叉编译）..."
	@ZIG="$(ZIG)" ./tests/verify_simd_c99_neon.sh; \
	VERIFY_EXIT=$$?; \
	if [ $$VERIFY_EXIT -ne 0 ]; then \
		echo "✗ SIMD C99 NEON 验证失败"; \
		exit 1; \
	fi
	@echo ""
	@echo "✓ hosted 验证通过（自举 + 测试 + 证明优化 + 默认顶层函数发射 + SIMD select C + @syscall C99 + SIMD NEON）"

# 备份（依赖 check 通过）：多文件 C 产物目录 -> backup/uyacache（与 make uya 一致）
backup: check
	@echo "备份多文件 C 目录 src/.uyacache -> backup/uyacache …"
	@if [ ! -f src/.uyacache/Makefile ]; then \
		echo "错误: src/.uyacache/Makefile 不存在（请先 make uya）"; \
		exit 1; \
	fi
	@rm -rf backup/uyacache
	@mkdir -p backup
	@cp -a src/.uyacache backup/uyacache
	@echo "✓ 备份完成: backup/uyacache"

# 单文件 C 种子：更新 bin/uya.c 与 backup/uya.c（from-c / release 依赖单文件）
backup-seed:
	@echo "单文件 C 编译（UYA_SINGLE_FILE_C=1）以更新 bin/uya.c 与 backup/uya.c …"
	@bash -c 'ulimit -s 32768 && cd src && UYA_SINGLE_FILE_C=1 UYA_SPLIT_C=0 UYA_SPLIT_C_DIR= UYA_MULTI_FILE_C= UYA_SPLIT_C_MIRROR= CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static CFLAGS="$(CFLAGS) -fno-stack-protector" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e --nostdlib'
	@cp src/build/uya.c bin/uya.c
	@mkdir -p backup
	@cp bin/uya.c backup/uya.c
	@$(MAKE) from-c >/dev/null
	@echo "✓ backup/uya.c 与 bin/uya.c 已更新（单文件种子）"

# 验证 + 多文件备份 + 单文件种子（提交前完整备份）
backup-all:backup backup-seed

# 发布版本：验证 + 多文件备份 + 单文件种子 + 构建优化版本
# 与 from-c 一致：Linux x86_64 的 nostdlib 种子含裸 _start，不可直接 cc uya.c（会与 Scrt1 _start 冲突），须 crti + .o + crtn 链接
release: clean from-c uya b check backup-seed
	@echo "=========================================="
	@echo "构建发布版本 (release)"
	@echo "=========================================="
	@echo "编译优化版本 bin/uya ..."
	@HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" \
		CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" \
		LDFLAGS="$(LDFLAGS)" \
		bash -c 'set -e; ulimit -s 32768 2>/dev/null || true; \
		if grep -qF "__attribute__((naked)) void _start(void)" bin/uya.c 2>/dev/null \
			&& [ "$$HOST_OS" = "linux" ] && [ "$$HOST_ARCH" = "x86_64" ]; then \
			echo "nostdlib 种子：-O3 -DNDEBUG，crti.o + uya.o + crtn.o 链接（同 from-c）..."; \
			$$CC_DRIVER $$CC_TARGET_FLAGS -std=c99 -O3 -fno-builtin -DNDEBUG -fno-stack-protector -c bin/uya.c -o bin/.release.o; \
			CRTI=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crti.o); \
			CRTN=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crtn.o); \
			if [ ! -f "$$CRTI" ] || [ "$$CRTI" = "crti.o" ] || [ ! -f "$$CRTN" ] || [ "$$CRTN" = "crtn.o" ]; then \
				echo "错误: 无法解析 crti.o/crtn.o，无法链接 nostdlib 版 release"; exit 1; \
			fi; \
			$$CC_DRIVER $$CC_TARGET_FLAGS -fno-stack-protector -no-pie -nostdlib -static \
				-o bin/uya "$$CRTI" bin/.release.o "$$CRTN" $$LDFLAGS; \
			rm -f bin/.release.o; \
		else \
			$$CC_DRIVER $$CC_TARGET_FLAGS -std=c99 -O3 -fno-builtin -DNDEBUG bin/uya.c -o bin/uya $$LDFLAGS; \
		fi'
	@strip bin/uya
	@echo ""
	@echo "✓ 发布版本构建完成: bin/uya"
	@ls -la bin/uya
	@echo ""
	@echo "优化选项: -O3 -fno-builtin -DNDEBUG"
	@echo "已剥离调试符号 (strip)"

# 安装编译器、标准库源码树与 tests/（需系统 install(1)；标准库排除 lib/build）
# tests 安装会排除常见中间目录与二进制产物（避免将本地测试构建垃圾安装到目标目录）
install:
	@if [ ! -f bin/uya ]; then \
		echo "bin/uya 不存在，先执行 from-c ..."; \
		$(MAKE) from-c; \
	fi
	@echo "安装 uya -> $(INSTALL_DEST_ROOT)$(INSTALL_BINDIR)/uya"
	@install -d "$(INSTALL_DEST_ROOT)$(INSTALL_BINDIR)"
	@install -m 755 bin/uya "$(INSTALL_DEST_ROOT)$(INSTALL_BINDIR)/uya"
	@echo "安装标准库 -> $(INSTALL_DEST_ROOT)$(LIBDIR)/"
	@install -d "$(INSTALL_DEST_ROOT)$(LIBDIR)"
	@for entry in lib/*; do \
		if [ ! -e "$$entry" ]; then continue; fi; \
		base=$$(basename "$$entry"); \
		if [ "$$base" = "build" ]; then continue; fi; \
		cp -a "$$entry" "$(INSTALL_DEST_ROOT)$(LIBDIR)/"; \
	done
	@echo "安装文档 -> $(INSTALL_DEST_ROOT)$(DOCDIR)/"
	@install -d "$(INSTALL_DEST_ROOT)$(DOCDIR)"
	@for f in uya_ai_prompt.md uya.md grammar_formal.md builtin_functions.md union_memory_layout.md; do \
		if [ ! -f "docs/$$f" ]; then echo "错误: 缺少 docs/$$f"; exit 1; fi; \
		install -m 644 "docs/$$f" "$(INSTALL_DEST_ROOT)$(DOCDIR)/$$f"; \
	done
	@echo "安装测试树 -> $(INSTALL_DEST_ROOT)$(TESTSDIR)/"
	@if [ ! -d tests ]; then echo "错误: tests 目录不存在"; exit 1; fi
	@rm -rf "$(INSTALL_DEST_ROOT)$(TESTSDIR)"
	@install -d "$(INSTALL_DEST_ROOT)$(TESTSDIR)"
	@cp -a tests/. "$(INSTALL_DEST_ROOT)$(TESTSDIR)/"
	@rm -rf "$(INSTALL_DEST_ROOT)$(TESTSDIR)/programs/build" \
		"$(INSTALL_DEST_ROOT)$(TESTSDIR)/build" \
		"$(INSTALL_DEST_ROOT)$(TESTSDIR)/.uyacache"
	@find "$(INSTALL_DEST_ROOT)$(TESTSDIR)" -type f \( \
		-name '*.o' -o -name '*.obj' -o -name '*.a' -o -name '*.so' -o -name '*.dylib' -o -name '*.exe' -o -name '*.out' \
	\) -delete
	@echo "✓ 安装完成: $(INSTALL_DEST_ROOT)$(INSTALL_BINDIR)/uya + $(INSTALL_DEST_ROOT)$(LIBDIR)/ + $(INSTALL_DEST_ROOT)$(DOCDIR)/ + $(INSTALL_DEST_ROOT)$(TESTSDIR)/"

# 从备份恢复 bin/uya.c
restore:
	@echo "从备份恢复 bin/uya.c ..."
	@if [ ! -f backup/uya.c ]; then \
		echo "错误: backup/uya.c 不存在"; \
		exit 1; \
	fi
	@mkdir -p bin
	@cp backup/uya.c bin/uya.c
	@echo "✓ 恢复完成: bin/uya.c"
	@ls -la bin/uya.c

# 显示帮助信息
help:
	@echo "Uya 项目 Makefile"
	@echo ""
	@echo "编译选项（可通过环境变量覆盖）:"
	@echo "  HOST_OS  = $(HOST_OS)"
	@echo "  HOST_ARCH= $(HOST_ARCH)"
	@echo "  TARGET_OS= $(TARGET_OS)"
	@echo "  TARGET_ARCH= $(TARGET_ARCH)"
	@echo "  TARGET_TRIPLE = $(TARGET_TRIPLE)"
	@echo "  RUNTIME_MODE = $(RUNTIME_MODE)"
	@echo "  LINK_MODE = $(LINK_MODE)"
	@echo "  TOOLCHAIN = $(TOOLCHAIN)"
	@echo "  ZIG      = $(ZIG)"
	@echo "  CC       = $(CC)"
	@echo "  CC_DRIVER= $(CC_DRIVER)"
	@echo "  CC_TARGET_FLAGS = $(CC_TARGET_FLAGS)"
	@echo "  CFLAGS   = $(CFLAGS)"
	@echo "  LDFLAGS  = $(LDFLAGS)"
	@echo ""
	@echo "用法示例:"
	@echo "  CFLAGS='-std=c99 -O0 -g -fno-builtin' make from-c    # 覆盖默认（默认含 -Werror）"
	@echo "  CFLAGS='-std=c99 -O2 -fno-builtin -Werror' make uya   # 使用 O2 优化构建"
	@echo "  TOOLCHAIN=zig ZIG=$(ZIG) make uya-hosted # 使用 zig cc hosted 构建"
	@echo ""
	@echo "可用目标:"
	@echo "  make from-c        - 从 bin/uya.c 构建（零依赖）"
	@echo "  make uya           - 构建自举编译器（默认 --nostdlib，静态链接）"
	@echo "  make uya-hosted    - 构建自举编译器（hosted 主线）"
	@echo "  make uya-std       - 构建自举编译器（标准库链接，用于调试）"
	@echo "  make uya-safety    - 构建自举编译器（启用内存安全检查）"
	@echo "  make b             - 自举验证：编译器编译自身，验证输出一致性"
	@echo "  make b-hosted      - hosted 自举验证"
	@echo "  make bench-compile-stats ARGS='--runs 3' - 抓取 CompileStats 基准数据"
	@echo "  make tests         - 运行测试套件（并行数默认 CPU 核数，UYA_TEST_JOBS=N 可改；默认不打印每条通过的 ✓）"
	@echo "  make tests-hosted  - 运行 hosted 主测试集（同上，默认 --hide-pass）"
	@echo "  make tests e       - 运行所有测试，最小输出（仅失败详情，等同脚本 -e）"
	@echo "  make tests-uya     - 快捷方式：测试自举编译器"
	@echo "  make tests-uya e   - 同上 + 最小输出（-e）"
	@echo "  make outlibc       - 输出标准库为 C 代码（使用自举编译器）"
	@echo "  make check         - 验证（自举 + 测试），不备份"
	@echo "  make check-hosted  - hosted 验证（自举 + 测试），不备份"
	@echo "  make backup        - 验证 + 备份多文件 C 目录 backup/uyacache（与 make uya 一致）"
	@echo "  make backup-seed   - 单文件 C 重编译，更新 bin/uya.c 与 backup/uya.c（from-c / release 用）"
	@echo "  make backup-all    - backup + backup-seed（提交前完整备份）"
	@echo "  make release       - 发布：clean+自举验证+backup-seed 后 -O3 -DNDEBUG 重链（nostdlib 种子同 from-c 用 crti/crtn）+ strip"
	@echo "  make install       - 安装 uya、lib/、前缀/docs/、前缀/tests/；BINDIR/LIBDIR/DOCDIR/TESTSDIR/DESTDIR"
	@echo "  make restore       - 从 backup/uya.c 恢复 bin/uya.c"
	@echo "  make clean         - 清理所有构建产物"
	@echo "  make help          - 显示此帮助信息"
	@echo ""
	@echo "示例:"
	@echo "  make from-c                          # 从 C99 代码构建（首次克隆后）"
	@echo "  make uya && make b && make tests-uya # 完整构建和自举验证"
	@echo "  make tests                           # 运行所有测试（默认省略通过的 ✓）"
	@echo "  make tests e                         # 运行所有测试，最小输出"
	@echo "  make clean && make from-c            # 清理后从备份恢复并构建"
	@echo '  make install PREFIX=$$HOME/.local   # ~/.local/bin/uya + ~/.local/lib/{std,libc,...}'
	@echo "  make install BINDIR=out              # out/bin/uya + out/lib/（BINDIR 作前缀，同 PREFIX 布局）"
	@echo "  make install BINDIR=/custom/bin      # 路径以 bin 结尾：可执行目录本身 + /custom/lib/"
	@echo "  make install LIBDIR=/other/lib       # 显式标准库目录（通常需配合 export UYA_ROOT）"
	@echo "  make install DOCDIR=/path/docs       # 显式文档目录（默认 前缀/docs）"
	@echo "  make install TESTSDIR=/path/tests    # 显式测试目录（默认 前缀/tests）"
	@echo ""
	@echo "macOS: hosted 主线见 docs/macos_hosted_smoke.md；备份 uya.c 为 Linux nostdlib 时 from-c 不可用。"
