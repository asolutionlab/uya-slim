---
name: SIMD设计路线
overview: 将 `@vector(T, N)` / `@mask(N)` 正式纳入语言内建，先落最小语义与前端支持；再将 `@vector` / `@mask` 接到真实 SIMD lowering；最后在 `std.json` 等场景以 `@vector`/`@mask` 为主做加速、`@asm` 可选补充，并保留 benchmark 与标量回退。
todos:
  - id: spec-builtin
    content: 定稿 `@vector(T, N)` / `@mask(N)` 的语法、边界和第一阶段最小语义
    status: pending
  - id: frontend-core
    content: 实现 AST、Parser、Checker 与最小回退 codegen，先保证语义、自举和测试稳定
    status: pending
  - id: backend-simd-lowering
    content: 把 `@vector` / `@mask` 接到真实 SIMD lowering，并保留标量回退
    status: pending
  - id: json-vector-asm-pilot
    content: std.json Stage 1 优先 `@vector`/`@mask`；可选 `@asm`（AVX2/NEON）补充；运行时检测与 benchmark
    status: pending
  - id: verification
    content: 按仓库流程纳入 `make check`、双路径测试与提交前 `make clean && make backup`
    status: pending
isProject: false
---

# SIMD 设计评审后计划

## 结论

将 `@vector(T, N)` 与 `@mask(N)` 正式纳入语言内建，不再只作为远期候选。为了控制风险，采用“语义先落地、性能后兑现”的两段式计划：

- 语言层先落最小类型系统与最小运算规则，优先保证 parser、checker、codegen、测试和自举稳定。
- 性能验证在 **`std.json` 等库内优先用 `@vector`/`@mask`** 表达可向量化热点（当前即与标量 struct 回退共存；lowering 落地后自动获益）；**可选**再以 `@asm` 做平台裸指令补充，沿用现有 `std.cfg(...)` / `@asm_target()` 与库内运行时分发。
- 不新增新的条件编译或目标特性内建。

关键依据：

- 现有泛型只接受类型参数，不支持值参数，`[docs/grammar_formal.md](docs/grammar_formal.md)` 与 `[src/parser/types.uya](src/parser/types.uya)` 都体现了这一点。
- 现有比较表达式统一返回 `bool`，因此把 `@mask(N)` 一并纳入语言内建，比延后掩码设计更稳妥，见 `[src/checker/check_expr_extra.uya](src/checker/check_expr_extra.uya)`。
- 现有条件裁枝主要依赖 `std.cfg(...)` 的解析期分支，见 `[src/parser/main.uya](src/parser/main.uya)`。
- 目标/平台区分已有 `@asm_target()` 可复用，运行时分发更适合放在库内辅助层，而不是再扩一套新的目标特性查询内建。
- 项目路线已将 SIMD 定位为低优先级未来扩展或标准库可选加速，见 `[docs/compiler_status.md](docs/compiler_status.md)`、`[docs/todo_json.md](docs/todo_json.md)`、`[docs/json_design.md](docs/json_design.md)`；本计划是在该基础上把语言内建与库内试点并行推进。

## 阶段 1：规范定稿

- 更新 `[docs/uya.md](docs/uya.md)`：把 `@vector(T, N)` / `@mask(N)` 定义为语言内建类型构造器，明确标量基线、显式向量化、无自动向量化。
- 更新 `[docs/grammar_formal.md](docs/grammar_formal.md)`：把 `vector_type` / `mask_type` 纳入 `type` 语法，并补齐相关说明。
- 更新 `[docs/todo_mini_to_full.md](docs/todo_mini_to_full.md)`：增加 SIMD 语言内建里程碑与分阶段落地路径。
- 锁定第一阶段语义边界：`T` 仅允许数值标量，`N` 仅允许编译期整数且第一版限制为字面量幂次；`@vector` 比较返回 `@mask(N)`；`@mask(N)` 不隐式转换为 `bool`。
- 第一阶段不纳入混合标量广播、通用 const generics、自动向量化、`shuffle/reduce`、新的 feature builtin。

## 阶段 2：编译器最小落地

- 词法/语法：在 `[src/lexer.uya](src/lexer.uya)`、`[src/ast.uya](src/ast.uya)`、`[src/parser/types.uya](src/parser/types.uya)` 中加入 `@vector(T, N)` / `@mask(N)` 的类型位置解析与 AST 节点。
- 类型系统：在 `[src/checker/types.uya](src/checker/types.uya)`、`[src/checker/type_from_ast.uya](src/checker/type_from_ast.uya)`、`[src/checker/check_expr_extra.uya](src/checker/check_expr_extra.uya)` 中加入 `TYPE_VECTOR` / `TYPE_MASK`、类型相等、比较结果、掩码运算与最小运算规则。
- 最小内建辅助：第一版只补 `@vector.splat`、`@vector.any`、`@vector.all` 三个必要 helper，避免 `@mask(N)` 无法落到控制流外部消费。
- Codegen 第一阶段优先做“保守正确”的回退 lowering：即使暂时不能映射到真实 SIMD，也先确保 `--c99`、`--uya --c99`、自举与测试可通过。
- 暂缓 `load/store/select/shuffle/reduce/widen/truncate` 等高复杂度能力，等**阶段 3（真实 lowering）**稳定后再扩。

## 阶段 3：真实 SIMD lowering 与语言扩展

- 把 `@vector` / `@mask` 接到真实 SIMD lowering，并始终保留标量回退路径（库侧已用 `@vector` 表达的代码在此阶段后自动获益）。
- 优先评估 `[src/codegen/c99/types.uya](src/codegen/c99/types.uya)`、`[src/codegen/c99/expr.uya](src/codegen/c99/expr.uya)`、`[src/codegen/c99/internal.uya](src/codegen/c99/internal.uya)` 的 lowering 接口，必要时补一层后端内部抽象。
- 第二阶段再扩充 `load/store/select`，第三阶段再评估 `shuffle/reduce`、混合标量广播与更完整的转换族。
- 即使进入真实 SIMD lowering，也继续沿用现有编译期/运行时分发方式，不扩展新的分支选择内建。

## 阶段 4：标准库性能试点（`std.json` 优先 `@vector`，`@asm` 可选）

- 在 `[docs/todo_json.md](docs/todo_json.md)` / `[docs/json_design.md](docs/json_design.md)` 的 JSON **Stage 1** 扫描路径中，**优先使用 `@vector`/`@mask`** 实现可向量化环；与阶段 2 的标量 struct 回退语义一致，无需等待阶段 3 即可编写与合并。
- **可选**：对仍需平台裸指令或手工调优的片段，保留 **AVX2/NEON `@asm`** 分支。
- 要求保持标量后备始终可用，并补 benchmark 验收（对比标量、`@vector` 与（若实现）`@asm`）。
- 编译期选路仅使用 `std.cfg(...)` / `@asm_target()`；运行时选路仅使用库内普通函数，不新增语言级 feature query。

## 验证策略

- 开发前先按仓库流程验证基线：执行 `make check`；若 `bin/uya` 缺失，则先 `make from-c`。
- 按 TDD 增加 `error_simd_*.uya` 与 `test_simd_*.uya`；先让测试失败，再实现最小功能使其通过。
- 每轮语言改动后都执行 `make check`，并同时覆盖 `--c99` 与 `--uya --c99`。
- `std.json` 试点单独保留 benchmark，对比标量路径、`@vector` 路径与（可选）`@asm` 路径。
- 准备提交时严格执行 `make clean && make backup`，不在测试失败或自举失败时推进提交。

## 规范草案

### BNF 草案

先按“第一阶段最小可实现”写入 `docs/grammar_formal.md`，避免一开始把 SIMD 语法设计成通用 const generic 系统。

```text
type           = base_type | pointer_type | array_type | slice_type
               | struct_type | union_type | interface_type | enum_type | tuple_type
               | atomic_type | error_union_type | function_pointer_type | extern_type
               | vector_type | mask_type

vector_type    = '@vector' '(' type ',' NUM ')'
mask_type      = '@mask' '(' NUM ')'
```

配套的表达式内建先只加最小集合：

```text
builtin_expr   = ...existing_builtins...
               | vector_builtin_expr

vector_builtin_expr
               = '@vector' '.' 'splat' '(' expr ')'
               | '@vector' '.' 'any'   '(' expr ')'
               | '@vector' '.' 'all'   '(' expr ')'
```

语法说明：

- `NUM` 在第一阶段表示字面量通道数；“编译期整数常量”可以留到后续阶段再放宽。
- `vector_type` 中的 `type` 在语法层允许复用现有 `type`，但语义层会进一步限制元素类型。
- 第一阶段不引入 `@vector<T>(N)`、`Vector(T, N)`、也不引入 `@mask<T>` 或任何新的目标特性查询语法。

### 类型检查规则草案

#### 1. 类型构造合法性

- `@vector(T, N)` 中：
  - `T` 必须是第一阶段允许的数值标量类型。
  - 建议第一阶段只允许：`i8`、`i16`、`i32`、`i64`、`u8`、`u16`、`u32`、`u64`、`f32`、`f64`。
  - 第一阶段不允许：`bool`、`byte`、`usize`、指针、切片、结构体、接口、错误联合、另一个 `@vector(...)`。
- `@mask(N)` 中：
  - `N` 必须是正整数通道数。
  - 第一阶段要求 `N` 为 2 的幂，且建议先限制在 `2/4/8/16/32/64`。
- `@vector(T, N)` 与 `@mask(N)` 都是第一类值类型，可用于局部变量、常量、函数参数、函数返回值、结构体字段。
- 第一阶段不保证它们在 `extern` ABI、`export extern` ABI、`@asm` 约束类型中的可用性；这些场景后移到真实 lowering 阶段。

#### 2. 类型相等与赋值

- `@vector(T1, N1)` 与 `@vector(T2, N2)` 仅当 `T1 == T2` 且 `N1 == N2` 时类型相等。
- `@mask(N1)` 与 `@mask(N2)` 仅当 `N1 == N2` 时类型相等。
- 不存在向量与标量之间的隐式转换。
- 不存在不同元素类型、不同通道数之间的隐式转换。
- `@mask(N)` 不隐式转换为 `bool`。

#### 3. 运算规则

- 算术运算：
  - `+`、`-`、`*`、`/` 允许用于相同类型的 `@vector(T, N)`，结果类型仍为 `@vector(T, N)`。
  - 第一阶段只支持“向量对向量”运算，不支持标量广播语法糖。
- 位运算：
  - `&`、`|`、`^`、`~`、`<<`、`>>` 仅允许用于整数元素类型的 `@vector(T, N)`。
- 比较运算：
  - `==`、`!=`、`<`、`<=`、`>`、`>=` 允许用于相同类型的 `@vector(T, N)`。
  - 比较结果类型为 `@mask(N)`。
- 掩码运算：
  - `&`、`|`、`^`、`!` 允许用于 `@mask(N)`。
  - 第一阶段不允许把 `@mask(N)` 直接作为 `if` / `while` 条件。

#### 4. 最小内建辅助

- `@vector.splat(x)`：
  - 通过上下文目标类型构造 `@vector(T, N)`。
  - 仅当上下文能唯一确定目标向量类型时合法。
- `@vector.any(m)`：
  - 参数必须是 `@mask(N)`，返回 `bool`。
- `@vector.all(m)`：
  - 参数必须是 `@mask(N)`，返回 `bool`。

#### 5. 错误处理与证明系统边界

- 第一阶段不把 lane 级状态接入 `try/catch`。
- 向量运算的错误语义先与标量错误系统解耦，不新增“按 lane 抛错”的语言规则。
- 证明系统、边界检查、移动语义等仍按普通值类型处理；只有在真实 lowering 阶段再评估是否需要额外规则。

### 第一阶段功能边界

#### 纳入范围

- 语言内建类型：`@vector(T, N)`、`@mask(N)`。
- 最小运算：向量算术、整数向量位运算、向量比较、掩码逻辑运算。
- 最小内建：`@vector.splat`、`@vector.any`、`@vector.all`。
- 最小后端支持：C99 路径先做语义正确的标量回退 lowering。
- 测试覆盖：语法负例、类型负例、基本算术、比较、掩码规约、函数传参与返回值。

#### 暂缓范围

- 标量广播语法糖，如 `vec + 1`。
- `load/store/select/shuffle/reduce/widen/truncate/bitcast/convert`。
- 自动向量化、平台特性 builtin、通用 const generics。
- `extern` ABI、跨语言 ABI 稳定性、`@asm` 与 `@vector` 的直接互操作。
- “直接映射硬件寄存器”的性能承诺；第一阶段只保证语义正确，不保证零成本。

#### 与 `std.json` 阶段 4（库内试点）的关系

- 第一阶段的 `@vector` / `@mask` 是语言语义落地。
- **`std.json` Stage 1** 在路线图**阶段 4** 以 **`@vector`/`@mask` 为主**做加速实现；**可选** `@asm` 作补充。
- 与**阶段 3（真实 lowering）**并行不阻塞：库代码可先用标量回退的 `@vector` 编写；lowering 落地后同一代码路径自动获益。

## 可落文档内容

### A. `docs/grammar_formal.md` 拟稿

下面这段按当前 `docs/grammar_formal.md` 的写法组织，可直接拆到“类型系统”和“表达式”附近。

```md
### SIMD 类型

```

type           = base_type | pointer_type | array_type | slice_type
               | struct_type | union_type | interface_type | enum_type | tuple_type
               | atomic_type | error_union_type | function_pointer_type | extern_type
               | vector_type | mask_type

vector_type    = '@vector' '(' type ',' NUM ')'
mask_type      = '@mask' '(' NUM ')'

```

**说明**：
- `@vector(T, N)` 表示元素类型为 `T`、通道数为 `N` 的向量类型
- `@mask(N)` 表示 `N` 通道的掩码类型
- 第一阶段 `N` 仅允许字面量正整数
- 第一阶段 `N` 必须为 2 的幂，建议限制为 `2`、`4`、`8`、`16`、`32`、`64`
- `vector_type` 在语法层允许任意 `type` 作为第一个参数；语义层会进一步限制 `T` 必须为数值标量类型
- 第一阶段不引入 `@vector<T>(N)`、`Vector(T, N)`、通用 const generics 或新的目标特性查询语法

### SIMD 内建表达式

```

builtin_expr   = '@' ('sizeof' | 'alignof' | 'len' | 'max' | 'min' | 'params' | 'va_start' | 'va_end' | 'va_arg' | 'va_copy' | 'asm')
               | '@' ('mc_type' | 'mc_eval' | 'mc_ast' | 'mc_code' | 'mc_error' | 'mc_get_env' | 'mc_source') '(' expr_list ')'
               | vector_builtin_expr

vector_builtin_expr
               = '@vector' '.' 'splat' '(' expr ')'
               | '@vector' '.' 'any'   '(' expr ')'
               | '@vector' '.' 'all'   '(' expr ')'

```

**说明**：
- `@vector.splat(x)` 通过上下文目标类型构造向量值
- `@vector.any(m)` 接受 `@mask(N)` 并返回 `bool`
- `@vector.all(m)` 接受 `@mask(N)` 并返回 `bool`
- 第一阶段不引入 `@vector.load`、`@vector.store`、`@vector.select`、`@vector.shuffle`、`@vector.reduce_`*

### SIMD 语义规则（第一阶段）

- `@vector(T, N)` 与 `@vector(U, M)` 仅当 `T == U` 且 `N == M` 时类型相等
- `@mask(N)` 与 `@mask(M)` 仅当 `N == M` 时类型相等
- `@mask(N)` 不隐式转换为 `bool`
- `@vector(T, N)` 不与标量类型隐式互转
- 算术运算 `+`、`-`、`*`、`/` 可用于相同类型的 `@vector(T, N)`，结果类型保持不变
- 位运算 `&`、`|`、`^`、`~`、`<<`、`>>` 仅适用于整数元素类型的 `@vector(T, N)`
- 比较运算 `==`、`!=`、`<`、`<=`、`>`、`>=` 可用于相同类型的 `@vector(T, N)`，结果类型为 `@mask(N)`
- 掩码运算 `&`、`|`、`^`、`!` 可用于 `@mask(N)`
- 第一阶段不允许把 `@mask(N)` 直接作为 `if` / `while` 条件
```

### B. `docs/uya.md` 拟稿

下面这段按当前 `docs/uya.md` 的说明风格组织，更适合作为新的小节直接插入。

```md
## SIMD 向量类型（草案）

### 设计目标

- 与现有类型系统一致：`@vector(T, N)`、`@mask(N)` 都是第一类值类型
- 显式向量化：程序员决定何时使用向量类型，不提供自动向量化承诺
- 先保证语义正确：第一阶段允许标量回退 lowering，不要求立刻映射真实硬件寄存器
- 与现有条件编译体系一致：平台裁枝仍使用 `std.cfg(...)` / `@asm_target()`，不新增新的条件编译或目标特性内建

### 语法

```uya
type Vec4f32 = @vector(f32, 4);
type Vec8i32 = @vector(i32, 8);
type Mask8 = @mask(8);

fn cmp(a: @vector(i32, 4), b: @vector(i32, 4)) @mask(4) {
    return a < b;
}
```

### 类型规则

- `@vector(T, N)`：
  - `T` 表示元素类型
  - `N` 表示通道数
  - 第一阶段 `N` 必须是字面量正整数，并要求为 2 的幂
- `@mask(N)`：
  - 表示 `N` 通道的布尔掩码
  - 仅用于向量比较结果与掩码逻辑运算
- 第一阶段允许的向量元素类型建议限制为：
  - `i8`、`i16`、`i32`、`i64`
  - `u8`、`u16`、`u32`、`u64`
  - `f32`、`f64`
- 第一阶段不允许 `bool`、`byte`、`usize`、指针、切片、结构体、接口、错误联合、嵌套向量作为 `@vector` 元素类型

### 运算规则

- 向量算术：
  - `+`、`-`、`*`、`/` 作用于相同类型的 `@vector(T, N)`
  - 结果类型仍为 `@vector(T, N)`
- 向量位运算：
  - `&`、`|`、`^`、`~`、`<<`、`>>` 仅适用于整数元素类型的 `@vector(T, N)`
- 向量比较：
  - `==`、`!=`、`<`、`<=`、`>`、`>=` 作用于相同类型的 `@vector(T, N)`
  - 返回 `@mask(N)`
- 掩码逻辑运算：
  - `&`、`|`、`^`、`!` 作用于 `@mask(N)`
- 第一阶段不支持：
  - 向量与标量混合运算
  - 向量与不同元素类型/不同通道数向量之间的隐式转换
  - 将 `@mask(N)` 隐式转换为 `bool`

### 最小内建辅助

#### 1. `@vector.splat(x)`

- 功能：用标量值 `x` 构造所有通道都相同的向量
- 目标类型由上下文决定
- 当上下文无法唯一确定目标向量类型时，编译报错

```uya
const zeros: @vector(i32, 4) = @vector.splat(0);
const ones:  @vector(f32, 8) = @vector.splat(1.0);
```

#### 2. `@vector.any(m)`

- 参数：`m: @mask(N)`
- 返回值：`bool`
- 功能：只要任一通道为 true，则返回 true

#### 3. `@vector.all(m)`

- 参数：`m: @mask(N)`
- 返回值：`bool`
- 功能：仅当所有通道都为 true 时返回 true

```uya
const lt: @mask(4) = a < b;
if @vector.any(lt) {
    // 至少一个通道满足条件
}
```

### 第一阶段边界

第一阶段纳入：

- `@vector(T, N)`、`@mask(N)`
- 基本算术、整数位运算、比较、掩码逻辑运算
- `@vector.splat`、`@vector.any`、`@vector.all`
- 语义正确的标量回退 lowering

第一阶段暂缓：

- 标量广播语法糖，如 `vec + 1`
- `load/store/select/shuffle/reduce`
- `widen/truncate/bitcast/convert`
- 自动向量化
- 新的目标特性查询内建
- `extern` ABI 与跨语言 ABI 保证
- “零成本”性能承诺

### 错误处理

- 第一阶段不把 lane 级状态接入 `try/catch`
- 向量运算不引入新的“按 lane 抛错”语义
- 饱和运算、包装运算与更细的错误模型留待后续阶段设计

```

```

