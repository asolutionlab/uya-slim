# Uya v0.5.5 发布说明

**发布日期：** 2026年2月19日

## 概述

本版本主要进行了代码规范化工作，将代码中的魔法数字替换为命名常量，同时优化了编译选项。

## 主要变更

### 代码规范化

将代码中的魔法数字替换为命名常量，提高代码可读性和可维护性。

#### 新增常量 (internal.uya)

| 常量 | 值 | 用途 |
|------|-----|------|
| `C99_MAX_ERROR_IDS` | 256 | 错误名数量上限 |
| `C99_GENERIC_NAME_BUF_SIZE` | 128 | 泛型名称缓冲区大小 |
| `C99_MAX_INTERFACE_METHODS` | 128 | 接口方法数量上限 |
| `C99_TYPE_ARG_BUF_SIZE` | 256 | 类型参数缓冲区大小 |
| `C99_TYPE_ARG_BUF_LIMIT` | 250 | 类型参数缓冲区限制 |
| `C99_OUTPUT_FILENAME_BUF_SIZE` | 100 | 输出文件名缓冲区大小 |
| `C99_STRING_INTERP_BUF_SIZE` | 2048 | 字符串插值缓冲区大小 |
| `C99_STRING_INTERP_LIMIT` | 2046 | 字符串插值限制 |
| `C99_SUFFIX_BUF_SIZE` | 512 | 后缀缓冲区大小 |

#### 新增常量 (checker.uya)

| 常量 | 值 | 用途 |
|------|-----|------|
| `MAX_MONO_NAME_LEN` | 256 | 单态化名称最大长度 |
| `MAX_MONO_NAME_LIMIT` | 250 | 单态化名称限制 |

#### 新增常量 (parser.uya)

| 常量 | 值 | 用途 |
|------|-----|------|
| `MAX_GENERIC_NAME_BUF` | 512 | 泛型名称缓冲区大小 |

### 编译选项优化

移除 `-fwrapv` 编译选项。

**变更前：**
```bash
gcc -std=c99 -O3 -fwrapv -fno-builtin
```

**变更后：**
```bash
gcc -std=c99 -O3 -fno-builtin
```

测试验证：去掉 `-fwrapv` 后，编译器自举和所有测试均通过。

### Bug 修复

修复 `stmt.uya` 中变量赋值错误：

```diff
- j2 = j + 1;
+ j2 = j2 + 1;
```

## 测试状态

- 自举验证：✓ 通过
- 单元测试：393/393 通过

## 受影响文件

- `Makefile`
- `src/compile.sh`
- `src/checker.uya`
- `src/codegen/c99/internal.uya`
- `src/codegen/c99/expr.uya`
- `src/codegen/c99/function.uya`
- `src/codegen/c99/main.uya`
- `src/codegen/c99/stmt.uya`
- `src/codegen/c99/structs.uya`
- `src/codegen/c99/types.uya`
- `src/codegen/c99/utils.uya`
- `src/parser.uya`

## 升级指南

直接使用新版本编译器即可，无需特殊升级步骤。

```bash
make from-c
make check
```
