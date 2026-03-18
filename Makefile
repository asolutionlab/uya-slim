# Uya 项目根目录 Makefile
# 提供统一的构建和测试入口

.PHONY: all from-c uya uya-hosted uya-std uya-nostdlib b b-hosted tests tests-hosted tests-uya outlibc c e clean check check-hosted backup restore release help

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
CFLAGS ?= -std=c99 -O0 -g -fno-builtin
LDFLAGS ?=

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
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS -c bin/uya.c -o bin/.from_c.o; \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS -c -DUYA_HOST_EXE_PATH_SYSCALL src/host_executable_path.c -o bin/.host_executable_path.o; \
			CRTI=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crti.o); \
			CRTN=$$($$CC_DRIVER $$CC_TARGET_FLAGS -print-file-name=crtn.o); \
			if [ ! -f "$$CRTI" ] || [ "$$CRTI" = "crti.o" ] || [ ! -f "$$CRTN" ] || [ "$$CRTN" = "crtn.o" ]; then \
				echo "错误: 当前工具链无法解析 crti.o/crtn.o，无法用 from-c 链接 nostdlib 版 uya.c"; exit 1; \
			fi; \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS -no-pie -nostdlib -static \
				-o bin/uya "$$CRTI" bin/.from_c.o bin/.host_executable_path.o "$$CRTN" $$LDFLAGS; \
			rm -f bin/.from_c.o bin/.host_executable_path.o; \
		else \
			$$CC_DRIVER $$CC_TARGET_FLAGS $$CFLAGS bin/uya.c src/host_executable_path.c -o bin/uya $$LDFLAGS; \
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
	@bash -c 'ulimit -s 32768 && cd src && CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e --nostdlib'
	@echo ""
	@echo "更新 bin/uya.c ..."
	@cp src/build/uya.c bin/uya.c
	@echo "✓ bin/uya.c 已更新"
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
	@bash -c 'ulimit -s 32768 && cd src && CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e'
	@echo ""
	@echo "更新 bin/uya.c ..."
	@cp src/build/uya.c bin/uya.c
	@echo "✓ bin/uya.c 已更新"
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
	@bash -c 'ulimit -s 32768 && cd src && CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e --safety-proof'
	@echo ""
	@echo "✓ 自举编译器（内存安全版）构建完成: bin/uya"

# 自举验证：用自举编译器编译自身，验证输出一致性
b: uya
	@echo "=========================================="
	@echo "自举验证：编译器编译自身，验证输出一致性"
	@echo "=========================================="
	@bash -c 'ulimit -s 32768 && cd src && CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e -b --nostdlib'
	@echo ""
	@echo "✓ 自举验证完成"

# hosted 自举验证：用 hosted 编译器编译自身，验证输出一致性
b-hosted: uya-hosted
	@echo "=========================================="
	@echo "hosted 自举验证：编译器编译自身，验证输出一致性"
	@echo "=========================================="
	@bash -c 'ulimit -s 32768 && cd src && CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" ./compile.sh --c99 -e -b'
	@echo ""
	@echo "✓ hosted 自举验证完成"

# 运行测试：默认使用 tests/run_programs_parallel.sh 并行测试（可 -j N 控制线程数）
# 用法: make tests [e] [其他参数]
# 示例: make tests e
#       make tests test_file.uya
tests:
	@HAS_E=$$(echo "$(MAKECMDGOALS)" | grep -qE '\be\b' && echo "yes" || echo "no"); \
	OTHER_ARGS=$$(echo "$(MAKECMDGOALS)" | sed 's/tests//g' | sed 's/\be\b//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	echo "=========================================="; \
	echo "测试自举编译器 (uya)"; \
	echo "=========================================="; \
	$(MAKE) uya >/dev/null 2>&1; \
	if [ "$$HAS_E" = "yes" ]; then \
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 -e $$OTHER_ARGS; \
	else \
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 $$OTHER_ARGS; \
	fi; \
	echo ""; \
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
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99 -e $$OTHER_ARGS; \
	else \
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99 $$OTHER_ARGS; \
	fi; \
	echo ""; \
	echo "✓ hosted 测试完成"

# 快捷目标：测试自举编译器（默认 tests/run_programs_parallel.sh 并行）
tests-uya:
	@HAS_E=$$(echo "$(MAKECMDGOALS)" | grep -qE '\be\b' && echo "yes" || echo "no"); \
	$(MAKE) uya >/dev/null 2>&1; \
	echo "=========================================="; \
	echo "测试自举编译器 (uya)"; \
	echo "=========================================="; \
	if [ "$$HAS_E" = "yes" ]; then \
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99 -e; \
	else \
		CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99; \
	fi

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
check: b
	@echo "=========================================="
	@echo "运行测试验证..."
	@echo "=========================================="
	@CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=nostdlib LINK_MODE=static ./tests/run_programs_parallel.sh --uya --c99; \
	TEST_EXIT=$$?; \
	if [ $$TEST_EXIT -ne 0 ]; then \
		echo ""; \
		echo "✗ 测试失败"; \
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
	@echo "✓ 验证通过（自举 + 测试 + 证明优化）"

# hosted 验证：普通链接自举 + 主测试 + 证明优化
check-hosted: b-hosted
	@echo "=========================================="
	@echo "运行 hosted 测试验证..."
	@echo "=========================================="
	@CC="$(CC)" CC_DRIVER="$(CC_DRIVER)" CC_TARGET_FLAGS="$(CC_TARGET_FLAGS)" HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" TARGET_OS="$(TARGET_OS)" TARGET_ARCH="$(TARGET_ARCH)" TARGET_TRIPLE="$(TARGET_TRIPLE)" TOOLCHAIN="$(TOOLCHAIN)" ZIG="$(ZIG)" RUNTIME_MODE=hosted LINK_MODE="$(LINK_MODE)" TEST_PROFILE=hosted ./tests/run_programs_parallel.sh --uya --c99; \
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
	@echo "✓ hosted 验证通过（自举 + 测试 + 证明优化）"

# 备份（依赖 check 通过）
backup: check
	@echo "备份 bin/uya.c ..."
	@mkdir -p backup
	@cp bin/uya.c backup/uya.c
	@echo "✓ 备份完成: backup/uya.c"

# 发布版本：验证 + 备份 + 构建优化版本
release: backup
	@echo "=========================================="
	@echo "构建发布版本 (release)"
	@echo "=========================================="
	@echo "编译优化版本 bin/uya ..."
	@HOST_OS="$(HOST_OS)" HOST_ARCH="$(HOST_ARCH)" bash -c 'set -e; \
	if grep -qF "__attribute__((naked)) void _start(void)" bin/uya.c 2>/dev/null \
		&& [ "$$HOST_OS" = "linux" ] && [ "$$HOST_ARCH" = "x86_64" ]; then \
		$(CC_DRIVER) $(CC_TARGET_FLAGS) -std=c99 -O3 -fno-builtin -DNDEBUG -c bin/uya.c -o bin/.rel.o; \
		$(CC_DRIVER) $(CC_TARGET_FLAGS) -std=c99 -O3 -fno-builtin -DNDEBUG -c -DUYA_HOST_EXE_PATH_SYSCALL src/host_executable_path.c -o bin/.rel_hep.o; \
		CRTI=$$($(CC_DRIVER) $(CC_TARGET_FLAGS) -print-file-name=crti.o); \
		CRTN=$$($(CC_DRIVER) $(CC_TARGET_FLAGS) -print-file-name=crtn.o); \
		$(CC_DRIVER) $(CC_TARGET_FLAGS) -std=c99 -O3 -fno-builtin -DNDEBUG -no-pie -nostdlib -static \
			-o bin/uya $$CRTI bin/.rel.o bin/.rel_hep.o $$CRTN $(LDFLAGS); \
		rm -f bin/.rel.o bin/.rel_hep.o; \
	else \
		$(CC_DRIVER) $(CC_TARGET_FLAGS) -std=c99 -O3 -fno-builtin -DNDEBUG bin/uya.c src/host_executable_path.c -o bin/uya $(LDFLAGS); \
	fi'
	@strip bin/uya
	@echo ""
	@echo "✓ 发布版本构建完成: bin/uya"
	@ls -la bin/uya
	@echo ""
	@echo "优化选项: -O3 -fno-builtin -DNDEBUG"
	@echo "已剥离调试符号 (strip)"
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
	@echo "  CFLAGS='-std=c99 -O0 -g' make from-c    # 使用调试选项构建"
	@echo "  CFLAGS='-std=c99 -O2' make uya          # 使用 O2 优化构建"
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
	@echo "  make tests         - 运行测试套件（默认 tests/run_programs_parallel.sh 并行）"
	@echo "  make tests-hosted  - 运行 hosted 主测试集"
	@echo "  make tests e       - 运行所有测试，只显示失败的测试"
	@echo "  make tests-uya     - 快捷方式：测试自举编译器"
	@echo "  make tests-uya e   - 快捷方式：测试自举编译器，只显示失败的测试"
	@echo "  make outlibc       - 输出标准库为 C 代码（使用自举编译器）"
	@echo "  make check         - 验证（自举 + 测试），不备份"
	@echo "  make check-hosted  - hosted 验证（自举 + 测试），不备份"
	@echo "  make backup        - 验证 + 备份 bin/uya.c"
	@echo "  make release       - 发布版本：验证 + 备份 + -O3 优化构建 + strip"
	@echo "  make restore       - 从 backup/uya.c 恢复 bin/uya.c"
	@echo "  make clean         - 清理所有构建产物"
	@echo "  make help          - 显示此帮助信息"
	@echo ""
	@echo "示例:"
	@echo "  make from-c                          # 从 C99 代码构建（首次克隆后）"
	@echo "  make uya && make b && make tests-uya # 完整构建和自举验证"
	@echo "  make tests                           # 运行所有测试"
	@echo "  make tests e                         # 运行所有测试，只显示错误"
	@echo "  make clean && make from-c            # 清理后从备份恢复并构建"
	@echo ""
	@echo "macOS: hosted 主线见 docs/macos_hosted_smoke.md；备份 uya.c 为 Linux nostdlib 时 from-c 不可用。"

