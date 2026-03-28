# Uya 语言 libc 内存分配器实现说明

## 概述

本文档记录了 Uya 语言 libc 内存分配器的 musl 风格实现方案。

## 当前实现（v0.6.0）- musl 风格空闲链表

### 核心特性

**数据结构：**
```uya
// 内存块头部（24 字节）
struct ChunkHeader {
    magic: u64,    // 魔数 0xDEADBEEF
    size: usize,   // 块大小，低 1 位=空闲标志
}

// 空闲块（40 字节，第一个字段必须是 header）
struct FreeChunk {
    header: ChunkHeader,  // 偏移 0-23
    prev: &FreeChunk,     // 偏移 24
    next: &FreeChunk,     // 偏移 32
}
```

**malloc:**
- 使用空闲链表管理已释放的内存块
- 首次适配算法查找合适大小的块
- 块分割：大块使用时分割剩余部分回到空闲链表
- 按需扩展：没有合适块时使用 mmap 扩展堆

**free:**
- 将块添加到空闲链表头部
- 简化版：暂不合并相邻空闲块（待实现）

**calloc:**
- 调用 malloc 分配内存
- 使用 memset 清零

**realloc:**
- 原地优化：新大小≤旧大小时直接返回
- 否则分配新内存 → 复制旧数据 → 释放旧内存

### 关键技术

#### 1. 使用 `as` 进行类型转换

```uya
// 从 mmap 返回的指针转换为 ChunkHeader
var hdr: &ChunkHeader = (ptr as &ChunkHeader);

// 同一指针转换为 FreeChunk（因为 header 是第一个字段）
var chunk: &FreeChunk = (ptr as &FreeChunk);

// 从 ChunkHeader 转换为 FreeChunk
var hdr: &ChunkHeader = ...;
var chunk: &FreeChunk = (hdr as &FreeChunk);
```

#### 2. 使用 `((ptr as &byte) as usize) == 0` 检查 null

```uya
fn is_null(ptr: &void) bool {
    return (((ptr as &byte) as usize) == 0);
}

// 使用示例
if is_null(chunk as &void) { return null; }
if !is_null(chunk.prev as &void) { ... }
```

#### 3. 位运算替代方案

```uya
// 检查奇数（代替 size & 1）
fn is_free(hdr: &ChunkHeader) bool {
    return ((hdr.size as i64) % (2 as i64)) != 0;
}

// 清除低 1 位（代替 size & ~1）
fn get_size(hdr: &ChunkHeader) usize {
    return ((hdr.size as i64) / (2 as i64)) as usize * 2;
}

// 16 字节对齐
fn align_up(size: usize) usize {
    if size == 0 { return 16; }
    var q: usize = size / 16;
    var r: usize = size - q * 16;
    if r == 0 { return size; }
    return (q + 1) * 16;
}
```

### 内存布局

```
内存地址：  [0          24        40      ]
            +-----------+---------+--------+
FreeChunk:  | ChunkHeader | prev  | next   |
            +-----------+---------+--------+
                         ↑
                    与 ChunkHeader 起始地址相同

因此可以安全转换：(chunk as &ChunkHeader) 或 (hdr as &FreeChunk)
```

### malloc 流程

```
1. 对齐大小到 16 字节
2. 查找空闲链表（首次适配）
3. 如果没有合适块：
   - 调用 mmap 扩展堆
   - 添加到空闲链表
   - 重新查找
4. 从空闲链表移除
5. 清除空闲标志
6. 分割块（如果剩余空间足够）
7. 返回用户指针
```

### free 流程

```
1. 获取块头部
2. 验证魔数
3. 转换为 FreeChunk
4. 添加到空闲链表头部
```

## 改进建议

### 短期
1. ✅ **空闲链表管理**：已实现
2. ✅ **块分割**：已实现
3. ⏳ **块合并**：free 时合并相邻空闲块（减少碎片）

### 长期
1. **块合并完整实现**：向前和向后合并
2. **最佳适配算法**：代替首次适配
3. **多个空闲链表**：按大小分类（类似 musl）

## 测试验证

```
总计：463 个测试
通过：463
失败：0
✓ 验证通过（自举 + 测试）
```

## 参考资料

- [musl libc malloc 实现](https://git.musl-libc.org/cgit/musl/tree/src/malloc/mallocng)
- [dlmalloc (Doug Lea's malloc)](http://gee.cs.oswego.edu/dl/html/malloc.html)
