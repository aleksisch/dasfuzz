# Zig compiler: eight bugs found by fuzzing

Found by grammar-based fuzzing of the Zig compiler. Five are crashes in
`lib/std/zig/AstGen.zig` (Bugs 1–5), two are `zig fmt` rewriting valid code
into code that no longer parses (Bugs 6–7), and one is a Sema crash while
reporting a dependency loop (Bug 8).

| | Component | Kind | Shows on a release binary | Upstream |
|---|---|---|---|---|
| Bug 1 | AstGen `forExpr` | out-of-bounds read | no | related: codeberg #37190 (same loop) |
| Bug 2 | AstGen `asmExpr` | out-of-bounds read | no | — |
| Bug 3 | AstGen `asmExpr` | out-of-bounds read | no | — |
| Bug 4 | AstGen `advanceSourceCursor` | assert, **valid code** | no | sibling of github #14332 |
| Bug 5 | AstGen `switchExpr` | assert | no | incomplete fix of github #18583 |
| Bug 6 | `zig fmt` | output does not parse | **yes** | — |
| Bug 7 | `zig fmt` | output does not parse | **yes** | github #18172, closed but never fixed |
| Bug 8 | Sema / `Zcu.zig` | unreachable | no | — |

"—" means no report found on GitHub. Codeberg's issue search API ignores the
query, so Codeberg still has to be searched by hand before filing.

## AstGen crashes (Bugs 1–5)

All five are in `lib/std/zig/AstGen.zig`, all reachable from a small source
file, and all still present in master. Bugs 1, 2 and 3 are out-of-bounds reads;
Bugs 4 and 5 are failed `assert`s. Bug 4 is triggered by **valid** Zig code;
Bug 5 is an incomplete fix of ziglang/zig#18583.

**Important for reproducing:** released Zig binaries are built in `ReleaseFast`,
where safety checks are off. There the out-of-bounds read silently returns
whatever is in adjacent memory, and the failed assert is simply not checked, so
the compiler prints a plausible error (or, for Bug 4, compiles the program)
instead of crashing. None of these bugs reproduces on an official release
binary, on the online playgrounds, or on Compiler Explorer. A compiler built in
`Debug` or `ReleaseSafe` — what a contributor building from source gets — panics.

| | Bug 1 | Bug 2 | Bug 3 | Bug 4 | Bug 5 |
|---|---|---|---|---|---|
| Site | `AstGen.zig:6816` / `6768` `forExpr` | `AstGen.zig:8661` `asmExpr` | `AstGen.zig:8700` `asmExpr` | `AstGen.zig:12915` `advanceSourceCursor` | `AstGen.zig:7738` / `7739` `switchExpr` |
| Panic | `index out of bounds: index 15, len 15` | `index out of bounds: index 16, len 16` | `index out of bounds: index 32, len 32` | `reached unreachable code` | `reached unreachable code` |
| Repro size | 23 bytes | 161 bytes | 311 bytes | 95 bytes | 122 bytes |
| Valid source | no | no | no | **yes** | no |
| In master | yes | yes | yes | yes | yes |

Bug 2 and Bug 3 are the same mistake on two lines and can share one report.

Versions checked: `0.17.0` (release) and `0.18.0-dev.146+35accc06e` (master).

---

## Bug 1 — `forExpr` reads one past the end of the token array

`capture_token` can point one past the last token, and `forExpr` reads it
without a bounds check.

### Repro

```zig
c:inline for(2,2..)|E|S
```

23 bytes, no trailing newline required. Run:

```
zig ast-check bug1_inline_for_capture.zig
```

### Observed, on a safety-checked compiler

```
thread N panic: index out of bounds: index 15, len 15
lib/std/zig/Ast.zig:89:35: in tokenTag
    return tree.tokens.items(.tag)[token_index];
lib/std/zig/AstGen.zig:6816:26: in forExpr
        if (tree.tokenTag(capture_token) != .pipe and tree.tokenTag(capture_token - 1) != .pipe) {
lib/std/zig/AstGen.zig:805:26: in expr
lib/std/zig/AstGen.zig:437:17: in reachableExprComptime
lib/std/zig/AstGen.zig:190:35: in generate
```

The file tokenizes to 15 tokens, so valid indices are 0..14; `capture_token`
is 15.

Related: codeberg ziglang/zig#37190 (opened 2026-10-11) reports a wrong
"extra capture in for loop" message and points at the same loop, which advances
`capture_token` by `ident_tok + 2` without checking for a comma. A fix there
should be checked against this repro too; it may be worth adding Bug 1 to that
issue rather than filing a new one.

### On an official release binary

```
error: redundant inline keyword in comptime scope
error: extra capture in for loop
```

Exit code 1. The read still happens, it just is not checked.

### A second read site, inside the loop

The out-of-range `capture_token` is also read earlier, inside the per-input
loop, when there are more inputs. A fix has to cover both reads.

```zig
c:for(0..,1..,2..)|d|i32
```

```
zig ast-check bug1b_for_three_inputs.zig
```

```
thread N panic: index out of bounds: index 18, len 18
lib/std/zig/AstGen.zig:6768:49: in forExpr
            const capture_is_ref = tree.tokenTag(capture_token) == .asterisk;
```

| `for` inputs, one capture, at EOF | panic site |
|---|---|
| 2 (`c:for(0..,1..)\|d\|i32`) | `AstGen.zig:6816` |
| 3 (`c:for(0..,1..,2..)\|d\|i32`) | `AstGen.zig:6768` |

### Cause

`forExpr` takes one capture per input. After reading a capture name it does
`capture_token = ident_tok + 2` (master `05671ced91`,
`lib/std/zig/AstGen.zig:6797`), assuming the next token is a comma. When there
are fewer captures than inputs, the token after the last name is the closing
`|`, so `+ 2` jumps into the loop body:

```
c:inline for(2,2..)|E|S
                   | E | S   <- `S` is taken as the capture for input 2
```

If the body starts with a name, that name is accepted as a capture and the walk
continues; near the end of the file it reads past the token array (this bug).
Otherwise the result is a wrong error at a wrong place, e.g. on `0.18.0-dev.146`:

```zig
var r: anyerror!void = {};
test { for (0..1, 0..2) |_| r catch |e| { _ = e; }; }
```
```
error: capture shadows declaration of 'r'
```

and `for (0..1, 0..1) |a| b;` gives `extra capture in for loop`, the wrong
message reported in codeberg #37190.

### Proposed fix

Step to the token after the name, and skip it only if it is a comma:

```diff
--- a/lib/std/zig/AstGen.zig
+++ b/lib/std/zig/AstGen.zig
@@ -6793,7 +6793,8 @@
             if (is_discard and capture_is_ref) {
                 return astgen.failTok(capture_token, "pointer modifier invalid on discard", .{});
             }
-            // Skip over the comma, and on to the next capture (or the ending pipe character).
-            capture_token = ident_tok + 2;
+            // Skip over the comma, if any, and on to the next capture (or the ending pipe character).
+            capture_token = ident_tok + 1;
+            if (tree.tokenTag(capture_token) == .comma) capture_token += 1;
 
             try emitDbgNode(parent_gz, input);
```

`capture_token` now never goes past the closing `|`, which the parser
guarantees exists, so both read sites stay in bounds. With too few captures
the next iteration lands on `|`, and the existing check reports
`for input is not captured`. The second loop over captures
(`AstGen.zig:6900-6907`, still `+ 2`) runs only after this one has checked
that captures and inputs match, so it is safe.

Tested against the `0.18.0-dev.146` std lib, whose `forExpr` is identical to
master's: patched a copy of its `lib/` and ran `Ast.parse` + `AstGen.generate`
in a Debug test with `--zig-lib-dir`.

| Input | Unpatched | Patched |
|---|---|---|
| `c:inline for(2,2..)\|E\|S` | panic, index 15 | `for input is not captured` |
| `c:for(0..,1..,2..)\|d\|i32` | panic, index 18 | `for input is not captured` |
| `for (0..1, 0..1) \|a\| b;` | `extra capture in for loop` | `for input is not captured` |
| `for (0..1, 0..2) \|_\| r catch \|e\| ...` | `capture shadows declaration of 'r'` | `for input is not captured` |
| `for (0..1, 0..1) \|a\| { ... }` | `for input is not captured` | same |
| `for (0..1) \|a, b\| ...` | `extra capture in for loop` | same |
| `\|a, b\|`, `\|a, b,\|`, `\|*a, i\|` | no error | no error |

Not built or tested with master itself. This also fixes the wrong message in
codeberg #37190.

---

## Bug 2 — `asmExpr` off-by-one in its own error path

The guard that rejects too many `asm` outputs reports the offending node by
indexing `full.outputs[16]`. With *exactly* 16 outputs the valid indices are
0..15, so the error path itself reads out of bounds.

```zig
// AstGen.zig:8661
return astgen.failNode(full.outputs[16], "too many asm outputs", .{});
```

### Repro

```zig
test{asm(1:[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n)::y);}
```

Sixteen asm outputs. Run:

```
zig ast-check bug2_asm_outputs_16.zig
```

### It is exactly 16, not "more than 16"

| asm outputs | result |
|---|---|
| 15 | `error: use of undeclared identifier 'n'` — correct |
| **16** | **`panic: index out of bounds: index 16, len 16`** |
| 17 | `error: too many asm outputs` — correct |

At 17 outputs `outputs[16]` exists, so the intended error is produced. The
boundary case is the only one that misbehaves, which is what makes it easy to
miss.

### Observed, on a safety-checked compiler

```
thread N panic: index out of bounds: index 16, len 16
lib/std/zig/AstGen.zig:8661:44: in asmExpr
        return astgen.failNode(full.outputs[16], "too many asm outputs", .{});
lib/std/zig/AstGen.zig:805:26: in expr
lib/std/zig/AstGen.zig:437:17: in reachableExprComptime
lib/std/zig/AstGen.zig:422:33: in reachableExpr
```

### On an official release binary

```
error: too many asm outputs
```

Exit code 1 — the message is right, but it was produced by reading past the
end of the slice.

### Proposed fix

Not compiled or tested: written against master `05671ced91`, where the guard
is at `lib/std/zig/AstGen.zig:8678-8680`.

The limit is 15 outputs (`outputs_buffer` right below is `[15]`), so the
first output over the limit is index 15. The guard guarantees
`full.outputs.len >= 16`, so `outputs[15]` always exists:

```diff
--- a/lib/std/zig/AstGen.zig
+++ b/lib/std/zig/AstGen.zig
@@ -8676,7 +8676,7 @@
         }
     }
     if (full.outputs.len >= 16) {
-        return astgen.failNode(full.outputs[16], "too many asm outputs", .{});
+        return astgen.failNode(full.outputs[15], "too many asm outputs", .{});
     }
     var outputs_buffer: [15]Zir.Inst.Asm.Output = undefined;
     const outputs = outputs_buffer[0..full.outputs.len];
```

With 17 or more outputs the error moves from the 17th output to the 16th,
which is the first one that does not fit.

---

## Bug 3 — the same off-by-one for asm inputs

A few lines below Bug 2, the guard for asm *inputs* has the same mistake, at
32 instead of 16.

```zig
// AstGen.zig:8700
if (full.inputs.len >= 32) {
    return astgen.failNode(full.inputs[32], "too many asm inputs", .{});
}
```

### Repro

```zig
test{asm volatile(1::[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n),[U]""(n));}
```

Thirty-two asm inputs. Run:

```
zig ast-check bug3_asm_inputs_32.zig
```

| asm inputs | result |
|---|---|
| 31 | `error: use of undeclared identifier 'n'` — correct |
| **32** | **`panic: index out of bounds: index 32, len 32`** |
| 33 | `error: too many asm inputs` — correct |

### Observed, on a safety-checked compiler

```
thread N panic: index out of bounds: index 32, len 32
lib/std/zig/AstGen.zig:8700:43: in asmExpr
        return astgen.failNode(full.inputs[32], "too many asm inputs", .{});
lib/std/zig/AstGen.zig:805:26: in expr
lib/std/zig/AstGen.zig:2653:41: in unusedResultExpr
```

### On an official release binary

```
error: too many asm inputs
```

### Proposed fix

Same fix as Bug 2, not compiled or tested. In master `05671ced91` the guard
is at `lib/std/zig/AstGen.zig:8717-8719`. The limit is 31 inputs
(`inputs_buffer` is `[31]`), so point at index 31:

```diff
--- a/lib/std/zig/AstGen.zig
+++ b/lib/std/zig/AstGen.zig
@@ -8715,7 +8715,7 @@
     }
 
     if (full.inputs.len >= 32) {
-        return astgen.failNode(full.inputs[32], "too many asm inputs", .{});
+        return astgen.failNode(full.inputs[31], "too many asm inputs", .{});
     }
     var inputs_buffer: [31]Zir.Inst.Asm.Input = undefined;
     const inputs = inputs_buffer[0..full.inputs.len];
```

---

## Bug 4 — local `var`/`const` with a computed type and `align(call())`

A local variable whose type expression and `align` expression both emit a
call (or a container declaration) trips the source-cursor assert. The program
is valid: a `ReleaseFast` compiler builds it and its test passes.

### Repro

```zig
fn f() type { return u8; } fn g() u29 { return 1; } test { var v: f() align(g()) = 0; _ = &v; }
```

95 bytes. Run:

```
zig ast-check bug4_local_var_align_call.zig
```

### Observed, on a safety-checked compiler

```
thread N panic: reached unreachable code
lib/std/debug.zig:439:14: in assert
lib/std/zig/AstGen.zig:12915:11: in advanceSourceCursor
    assert(i <= end);
lib/std/zig/AstGen.zig:10036:35: in callExpr
lib/std/zig/AstGen.zig:829:28: in expr
lib/std/zig/AstGen.zig:2382:20: in fullBodyExpr
lib/std/zig/AstGen.zig:2104:42: in comptimeExpr2
lib/std/zig/AstGen.zig:1990:25: in comptimeExpr
lib/std/zig/AstGen.zig:402:24: in typeExpr
```

### Cause

`varDecl` generates the `align` expression (`AstGen.zig:3138`) before the type
expression (`typeExpr` at `3158`, `3189` or `3258`). The source cursor only
moves forward. A call in `align(...)` advances it past the type; the call in
the type then asks to move it back, and `assert(i <= end)` fails.

### What triggers it

| Declaration | Result |
|---|---|
| `var v: f() align(g()) = 0;` in a function | **panic** |
| `const v: f() align(g()) = 0;` in a function | **panic** |
| `var v: struct { a: u8 } align(g()) = undefined;` in a function | **panic** |
| `var v: union { a: u8 } align(g()) = undefined;` in a function | **panic** |
| `var v: enum { a } align(g()) = .a;` in a function | **panic** |
| `var v: f() align(4) = 0;` in a function | ok |
| `var v: u8 align(g()) = 0;` in a function | ok |
| `var v: f() align(g()) = 0;` at container level | ok |

The struct/union/enum cases panic in `structDeclInner`, `unionDeclInner` and
`containerDecl` instead of `callExpr`, but the failing assert is the same:
anything in the type that moves the source cursor counts. One fix covers all
of them.

Closest upstream report: ziglang/zig#14332 (closed 2023), the same assert for
`*align(call()) [call()]u8`. That fix did not cover local variable
declarations.

### On an official release binary

```
$ zig ast-check bug4_local_var_align_call.zig   # no output, exit code 0
$ zig test bug4_local_var_align_call.zig
All 1 tests passed.
```

---

## Bug 5 — by-reference capture in an error switch, on any prong but the first

ziglang/zig#18583 (closed January 2024) reported that a by-reference capture
in an error switch hit an assert instead of the error
`error set cannot be captured by reference`. Its repro is fixed in master. Put
any prong *before* the by-reference one and the same assert fires again.

### Repro

```zig
test { const e: error{A,B}!u32 = error.A; e catch |err| switch (err) { error.B => {}, error.A => |*foo| { _ = foo; }, }; }
```

122 bytes. Run:

```
zig ast-check bug5_catch_switch_ref_capture.zig
```

The `if (e) |v| ... else |err| switch (err)` form fails the same way
(`bug5_if_else_switch_ref_capture.zig`).

A tag capture hits the next assert in the same block,
`assert(!any_has_tag_capture)` (`AstGen.zig:7739`), with the same rule: only
when an earlier prong comes first (`bug5_catch_switch_tag_capture.zig`):

```zig
test { const e: error{A,B}!u32 = error.A; e catch |err| switch (err) { error.B => {}, error.A => |foo, tag| { _ = foo; _ = tag; }, }; }
```

A release binary prints `error: cannot capture tag of error union` instead.
The fuzzer found 28 crashes at `7739` overnight (2026-10-13/14).

### Observed, on a safety-checked compiler

```
thread N panic: reached unreachable code
lib/std/debug.zig:439:14: in assert
lib/std/zig/AstGen.zig:7738:19: in switchExpr
            assert(!any_payload_is_ref); // should have failed by now
lib/std/zig/AstGen.zig:1033:34: in expr
lib/std/zig/AstGen.zig:2653:41: in unusedResultExpr
```

### Only the position of the `|*foo|` prong matters

| Switch prongs | Result |
|---|---|
| `error.A => \|*foo\| ...` (the #18583 repro) | `error: error set cannot be captured by reference` — correct |
| `error.B => {}, error.A => \|*foo\| ...` | **panic** |
| `error.B => {}, else => \|*foo\| ...` | **panic** |

Same for `catch |err| switch` and `if ... else |err| switch`, with or without a
switch label.

### Cause

`switchExpr` sets `any_payload_is_ref` in a pre-pass over **all** prongs
(`AstGen.zig:7155`). The user-facing error is only raised inside the per-prong
loop, when that loop reaches the by-reference prong (`AstGen.zig:7698`). But
every iteration also runs `assert(!any_payload_is_ref)` (`AstGen.zig:7738`). An
earlier prong without a capture reaches that assert while the flag is already
set by a later prong, before the loop gets to the error. The comment "should
have failed by now" holds only when the by-reference prong is first.

### On an official release binary

```
error: error set cannot be captured by reference
```

Exit code 1 — the right error, produced only because the assert is compiled
out.

---

## Bug 6 — `zig fmt` merges `..` and a following `.` into `...`

A slice or range whose end starts with a `.` (decl literal, enum literal,
anonymous literal) is written without the space, and `.. .` becomes the single
token `...`. The formatted file no longer parses.

### Repro

```zig
test {
    const s = "abc";
    _ = s[0.. .len];
}
```

```
$ zig ast-check fmt1_range_dot_merges_to_ellipsis.zig   # ok
$ zig fmt --stdin < fmt1_range_dot_merges_to_ellipsis.zig
test {
    const s = "abc";
    _ = s[0...len];
}
$ zig fmt --stdin < fmt1_range_dot_merges_to_ellipsis.zig | zig fmt --stdin
<stdin>:3:12: error: expected ']', found '...'
```

The same happens to `for` ranges: `for (0.. .{}) |a| {}` becomes
`for (0...{}) |a| {}` (`error: expected ',' after for operand`).

Reproduces on official release binaries (`0.17.0`, `0.18.0-dev.146`): this is
wrong output, not a safety check.

### Cause

The renderer writes `..` with no space after it, in two places in
`lib/std/zig/Ast/Render.zig` (master `05671ced91`):

- `.for_range` always renders `..` with `.none`.
- `renderSlice` adds spaces around `..` only when `nodeCausesSliceOpSpace` is
  true for the start or end node. That list is binary operators (`+`,
  `orelse`, ...); an enum literal like `.len` is not in it.

If the next token is `.`, the lexer reads the output `...` as one token
(`ellipsis3`). `..` is only valid in `for` ranges and slices, and `...` only in
switch ranges and varargs, so the merged output never parses.

### Proposed fix

Two lines: if the token after `..` is `.`, write one space after `..`.

```diff
--- a/lib/std/zig/Ast/Render.zig
+++ b/lib/std/zig/Ast/Render.zig
@@ -472,7 +472,7 @@
             const start, const opt_end = tree.nodeData(node).node_and_opt_node;
             try renderExpression(r, start, .none);
             if (opt_end.unwrap()) |end| {
-                try renderToken(r, tree.nodeMainToken(node), .none);
+                try renderToken(r, tree.nodeMainToken(node), if (tree.tokenTag(tree.nodeMainToken(node) + 1) == .period) .space else .none);
                 return renderExpression(r, end, space);
             } else {
                 return renderToken(r, tree.nodeMainToken(node), space);
@@ -1148,7 +1148,7 @@
     const after_start_space: Space = if (space_around_dots) .space else .none;
     const before_sentinel_space: Space = if (slice.ast.sentinel != .none) .space else .none;
     const after_dots_space: Space = if (slice.ast.end != .none)
-        if (space_around_dots) .maybe_space else .none
+        if (space_around_dots) .maybe_space else if (tree.tokenTag(tree.lastToken(slice.ast.start) + 2) == .period) .space else .none
     else
         before_sentinel_space;
```

In `renderSlice`, `lastToken(start) + 1` is `..` and `+ 2` is the token after
it.

| Input | Output |
|---|---|
| `s[0.. .len]` | `s[0.. .len]` |
| `s[0..     .len]` | `s[0.. .len]` |
| `for (0.. .{}) \|a\| {}` | `for (0.. .{}) \|a\| {}` |
| `s[0..len]`, `for (0..10)` | unchanged |
| `s[0 + 1.. .len]` | `s[0 + 1 .. .len]` (existing operator rule) |

Tested against the `0.18.0-dev.146` std lib, whose `renderSlice` and
`.for_range` are identical to master's: patched a copy of its `lib/`, and ran
a round trip (parse, render, re-parse, render, compare) with `--zig-lib-dir`.
Both repros fail unpatched and pass patched; `b[0..1]`, `d[0 + 0 .. 1]` and
`for (0..10)` render unchanged. Not built or tested with master itself.

Test to add to `lib/std/zig/parser_test.zig`:

```zig
test "zig fmt: range end starting with a period" {
    try testCanonical(
        \\const a = s[0.. .len];
        \\test {
        \\    for (0.. .{}) |_| {}
        \\}
        \\
    );
}
```

---

## Bug 7 — `zig fmt` duplicates the token before an `inline for`/`while`/`fn` switch item

When a switch prong is `inline` and its first item is a `for`, `while` or `fn`
expression, `zig fmt` emits the token *before* `inline` a second time: a stray
`{` on the first prong, a stray `,` on later ones.

### Repro

```zig
test {
    switch (@as(u8, 0)) {
        0 => {},
        inline for (.{}) |_| 0 => {},
        else => {},
    }
}
```

```
$ zig fmt --stdin < fmt2_inline_prong_loop_item.zig
test {
    switch (@as(u8, 0)) {
        0 => {},
        , inline for (.{}) |_| 0 => {},
        else => {},
    }
}
```

| First item of an `inline` prong | `zig fmt` output |
|---|---|
| `1` | correct |
| `if (c) 1 else 2` | correct |
| `(for (U) \|c\| 0)` | correct |
| `for (U) \|c\| 0` | **stray token** |
| `while (c) 1` | **stray token** |
| `fn () void` | **stray token, and `inline` is dropped**: `{ fn () void => {},` |

The likely cause is that `Ast.firstToken` of a `for`/`while`/fn-proto node
reaches back over a preceding `inline` keyword, so the prong's `inline` is
counted twice when rendering.

### Already reported, never fixed

This is github ziglang/zig#18172 ("zig fmt breaks with inline for loop inside
switch case"), with the identical repro. The issue was closed in May 2024, but
its fix, PR #18216, was closed **without being merged** in January 2024. The
#18172 repro still fails on `0.17.0` and `0.18.0-dev.146`. The `while` and
`fn` cases and the stray `,` on non-first prongs are not in that issue.

Reproduces on official release binaries.

61 of the 65 `zig fmt` failures in the corpus sweep are this bug (54 `for` or
`while`, 7 `fn`); the other 4 are Bug 6.

---

## Bug 8 — Sema: `extern fn` whose type depends on itself crashes the error reporter

### Repro

```zig
extern fn c() c;
test { _ = c; }
```

```
zig test -fno-emit-bin sema1_extern_fn_self_type.zig
```

### Observed, on a safety-checked compiler (`0.17.0` built `ReleaseSafe`)

```
thread N panic: reached unreachable code
src/Zcu.zig:1457:29: in span
src/Zcu.zig:5158:30: in addDependencyLoopErrorLine
src/Zcu.zig:5072:48: in addDependencyLoopErrors
src/Compilation.zig:4173:40: in anyErrors
src/Zcu/PerThread.zig:3697:27: in processExports
src/main.zig:4873:20: in updateModule
```

### On an official release binary

```
error: dependency loop with length 2
    t.zig:1:1: note: value of declaration 't.c' uses type of declaration 't.c' here
    extern fn c() c;
```

That is the intended error. In a safety-checked build, building that note
crashes.

### Cause

The note's source location is `.node_offset_var_decl_init`. Its handler in
`Zcu.zig` switches on the node tag and accepts only variable declarations and
`assign_destructure`; anything else is `unreachable`. Here the node is an
`extern fn` prototype, which has no init expression.

| Declaration | Result |
|---|---|
| `pub extern fn c() c;` | **panic** |
| `pub extern fn c(n: c) void;` | **panic** |
| `pub extern fn c(n: c) callconv(.c) void;` | **panic** |
| `pub fn c() c {}` | `error: value of declaration 't.c' depends on itself here` — correct |
| `pub fn c(n: c) void { _ = n; }` | same correct error |

### In master

Not run on master: that needs a safety-checked build of master's compiler.
The handler at `src/Zcu.zig:1447-1459` in master on Codeberg (commit
`05671ced91`, 2026-10-12) is identical to `0.17.0`.

### Proposed fix

Not compiled or tested: written against master `05671ced91` from reading the
code.

The bad location is created in `analyzeNavVal` (`src/Zcu/PerThread.zig`).
Every declaration gets an `init_src` of `.node_offset_var_decl_init`, and
when the declaration has a type body, that location is the reason recorded for
the "value uses type" dependency. If the type then depends on the value, the
dependency loop error resolves the location, and the handler finds an
`extern fn` prototype with no init expression.

The `unreachable` in `Zcu.zig` is correct: the caller should not ask for an
init node that does not exist. So the fix is in the caller. Declarations
without a value body (`extern fn`, `extern var`) point at the whole
declaration instead:

```diff
--- a/src/Zcu/PerThread.zig
+++ b/src/Zcu/PerThread.zig
@@ -1737,7 +1737,11 @@
     defer block.instructions.deinit(gpa);
 
     const ty_src = block.src(.{ .node_offset_var_decl_ty = .zero });
-    const init_src = block.src(.{ .node_offset_var_decl_init = .zero });
+    // Declarations without a value body (e.g. `extern fn`) have no init expression to point at.
+    const init_src = if (zir_decl.value_body != null)
+        block.src(.{ .node_offset_var_decl_init = .zero })
+    else
+        block.nodeOffset(.zero);
     const align_src = block.src(.{ .node_offset_var_decl_align = .zero });
     const section_src = block.src(.{ .node_offset_var_decl_section = .zero });
     const addrspace_src = block.src(.{ .node_offset_var_decl_addrspace = .zero });
```

- `var`/`const` with an init expression are unchanged: the note still points
  at the init expression.
- For `extern` declarations, the note points at the whole declaration. Before,
  a safety-checked compiler panicked, and a release compiler underlined
  whatever the undefined behaviour gave (`extern` at `1:1` above).
- The other uses of `init_src` in `analyzeNavVal` (coercion,
  `resolveFinalDeclValue`, `validateVarType` without a type body) only run
  when there is a value body, so they are unaffected.

Not chosen: making the `Zcu.zig` handler fall back to the whole node for
unexpected tags. That hides the wrong request instead of removing it.

To verify: build master with safety checks, run the repro and the three
`extern` rows from the table above, and add a case under
`test/cases/compile_errors/` that fixes the exact line and column of each
note.

---

## Confirming Bugs 1–5 against master without building the compiler

All of these bugs reproduce through `std.zig` directly, so a `Debug` build of a ten-line
program is enough — no full compiler build needed. Put the repro next to this
file as `repro.zig`:

```zig
const std = @import("std");
pub fn main() !void {
    var buf: [1 << 22]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const a = fba.allocator();
    const src: [:0]const u8 = @embedFile("repro.zig");
    const tree = try std.zig.Ast.parse(a, src, .{});
    var zir = try std.zig.AstGen.generate(a, tree);
    _ = &zir;
    std.debug.print("ok, {d} tokens\n", .{tree.tokens.len});
}
```

```
zig build-exe chk.zig -ODebug && ./chk
```

Run with master's `zig`, this panics at the sites above for every repro. Note
`Ast.parse` takes a `ParseOptions` struct on master (`.{}`), not a `Mode`.

---

## How they were found

AFL++ with a custom grammar mutator over the official Zig PEG grammar
(`ziglang/zig-spec`, `grammar/grammar.peg`), converted to the mutator's JSON
rule format. The target is `zig ast-check` — parser and AstGen only, about
1.4 ms per execution.

The compiler under test was built `ReleaseSafe` with
`-fsanitize-coverage-trace-pc-guard` and the LLVM backend. Both choices matter:

- `ReleaseSafe` keeps the safety checks, so an out-of-bounds read becomes a
  panic AFL can see. Against a `ReleaseFast` build neither of these bugs is a
  crash at all, and the campaign would report nothing.
- The self-hosted backend accepts `-fsanitize-coverage-trace-pc-guard` and
  silently emits no instrumentation (0 edges). Only `-fllvm` produces the
  guards. The pass also references `__sancov_lowest_stack`, which AFL's runtime
  does not define, so a one-line `__thread unsigned long` stub is needed to
  link.

First run: 2.18M executions, 18,174 corpus entries, two crashes (Bugs 1 and 2).

Second run (2026-10-12, 10–15 instances, ~2 hours): about 20M total
executions, 290 saved crashes. Every one was re-run against a `Debug` build of
master's `std.zig` (the program in the previous section, reading the file from
argv) and grouped by its first AstGen frame. All 290 belong to the bugs in this
document:

| Bug | Crashes |
|---|---|
| 4 | 269 |
| 1 | 10 |
| 3 | 6 |
| 2 | 4 |
| 5 | 1 |

Bug 4 is triggered so easily that it masks most other AstGen paths; patching it
locally in the fuzz target would let the campaign look past it.

## Offline sweeps over the corpus (Bugs 6–8)

The AFL corpus (59,809 unique inputs after deduplication) was also run through
two oracles outside the fuzzing loop:

- **`zig fmt`**: for every input that parses, format it, then format the
  output again. A crash, an output that no longer parses, or a second pass that
  changes the output is a bug. Result: no crashes, no idempotence failures, 65
  outputs that do not parse — all of them Bug 6 or Bug 7.
- **Sema**: for every input that passes `zig ast-check` (about 3%), append
  `test { @import("std").testing.refAllDecls(@This()); }` so that Sema does not
  skip unreferenced declarations, and run `zig test -fno-emit-bin`. Result: one
  crash, Bug 8.

The grammar fuzzer only optimises for parser and AstGen coverage, so few of its
programs are semantically meaningful; the Sema stage sees a narrow slice of
Sema. AFL instances running `zig fmt --check` as the target have since been
added.
