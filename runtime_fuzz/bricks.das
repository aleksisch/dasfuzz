options gen2
module bricks shared

require daslib/strings_boost
require daslib/random

var rng_seed : int4

// Type system for assembly constraints
enum DasType {
    tInt
    tUInt
    tFloat
    tDouble
    tInt64
    tUInt64
    tBool
    tString
    tFunc1Int       // 1-arg function: int -> int
    tFunc1UInt
    tFunc1Float
    tFunc1Double
    tFunc1Int64
    tFunc1UInt64
    tFunc2Int       // 2-arg function: (int, int) -> int
    tFunc2UInt
    tFunc2Float
    tFunc2Double
    tFunc2Int64
    tFunc2UInt64
}

// A typed symbol: (name, type)
bitfield SymFlags {
    nonzero
}

struct TypedSymbol {
    name : string
    sym_type : DasType
    flags : SymFlags
}

// Assembly constraint: precondition (what's needed) + postcondition (what's provided)
struct Constraint {
    pre : array<TypedSymbol>
    post : array<TypedSymbol>
}

enum BrickPlacement {
    IN_MAIN      // emitted inside main()
    TOP_LEVEL    // emitted before main() (functions, structs)
}

// A code brick: a fragment of code + its assembly constraint
// Template uses #s0#, #s1#, ... for symbols and #lit:TYPE# for random literals
struct Brick {
    code : string
    placement : BrickPlacement
    constraint : Constraint
}

// The pool of all available bricks
struct BrickPool {
    bricks : array<Brick>
}

// Surface name per type — table lookup, default "int" for the function types.
let TYPE_NAMES <- {
    DasType.tInt    => "int",
    DasType.tUInt   => "uint",
    DasType.tFloat  => "float",
    DasType.tDouble => "double",
    DasType.tInt64  => "int64",
    DasType.tUInt64 => "uint64",
    DasType.tBool   => "bool",
    DasType.tString => "string"
}

def type_name(t : DasType) : string {
    return TYPE_NAMES?[t] ?? "int"
}

// Literal template per type; %i%/%u%/%f%/%b%/%s% markers are filled with fresh
// randoms below. No-op markers (absent from the chosen template) cost nothing.
let LIT_TEMPLATES <- {
    DasType.tInt    => "%i%",
    DasType.tUInt   => "uint(%u%)",
    DasType.tFloat  => "%f%",
    DasType.tDouble => "%f%lf",
    DasType.tInt64  => "int64(%i%)",
    DasType.tUInt64 => "uint64(%u%)",
    DasType.tBool   => "%b%",
    DasType.tString => "%s%"
}

let LIT_STRINGS = fixed_array("hello", "world", "foo", "bar", "test", " ", "abc", "123", "Hello World", "")
let LIT_BOOLS = fixed_array("false", "true")

def random_literal(t : DasType) : string {
    // masks keep the index/low-bit non-negative (random_int can be negative)
    let str = LIT_STRINGS[(random_int(rng_seed) & 0x7fffffff) % length(LIT_STRINGS)]
    var r = LIT_TEMPLATES?[t] ?? "0"
    r = r |> replace("%i%", "{random_int(rng_seed) - 2}")
    r = r |> replace("%u%", "{random_int(rng_seed)}")
    r = r |> replace("%f%", "{random_float(rng_seed)}")
    r = r |> replace("%b%", LIT_BOOLS[random_int(rng_seed) & 1])
    r = r |> replace("%s%", "\"{str}\"")
    return r
}

// Arithmetic ops valid for numeric types
let ARITH_OPS = fixed_array("+", "-", "*")
let CMP_OPS = fixed_array("==", "!=", "<", ">", "<=", ">=")
let BITWISE_OPS = fixed_array("&", "|", "^", "<<", ">>")

def func1_type_for(t : DasType) : DasType {
    if (t == DasType.tInt) {
        return DasType.tFunc1Int
    } elif (t == DasType.tUInt) {
        return DasType.tFunc1UInt
    } elif (t == DasType.tFloat) {
        return DasType.tFunc1Float
    } elif (t == DasType.tDouble) {
        return DasType.tFunc1Double
    } elif (t == DasType.tInt64) {
        return DasType.tFunc1Int64
    } elif (t == DasType.tUInt64) {
        return DasType.tFunc1UInt64
    }
    return DasType.tFunc1Int
}

def func2_type_for(t : DasType) : DasType {
    if (t == DasType.tInt) {
        return DasType.tFunc2Int
    } elif (t == DasType.tUInt) {
        return DasType.tFunc2UInt
    } elif (t == DasType.tFloat) {
        return DasType.tFunc2Float
    } elif (t == DasType.tDouble) {
        return DasType.tFunc2Double
    } elif (t == DasType.tInt64) {
        return DasType.tFunc2Int64
    } elif (t == DasType.tUInt64) {
        return DasType.tFunc2UInt64
    }
    return DasType.tFunc2Int
}

def is_numeric(t : DasType) : bool {
    return t == DasType.tInt || t == DasType.tUInt || t == DasType.tFloat || t == DasType.tDouble || t == DasType.tInt64 || t == DasType.tUInt64
}

def is_integer(t : DasType) : bool {
    return t == DasType.tInt || t == DasType.tUInt || t == DasType.tInt64 || t == DasType.tUInt64
}

def make_sym(n : string; t : DasType; f : SymFlags = SymFlags(0)) : TypedSymbol {
    var s : TypedSymbol
    s.name = n
    s.sym_type = t
    s.flags = f
    return s
}

def sym_matches(candidate : TypedSymbol; required : TypedSymbol) : bool {
    if (candidate.sym_type != required.sym_type) {
        return false
    }
    // If required has nonzero flag, candidate must also have it
    if ((required.flags & SymFlags.nonzero) != SymFlags(0) && (candidate.flags & SymFlags.nonzero) == SymFlags(0)) {
        return false
    }
    return true
}

// Positional symbol helpers. A symbol's name is just its slot: inputs are numbered
// first (s0, s1, ...), outputs continue after them. Callers never hand-write a name,
// and templates keep using #s0#/#s1#/#s2# unchanged. `outp` lists ONLY new outputs —
// the old post passthrough (re-listing inputs) was dead, since the assembler records
// only symbols absent from `pre`.
def inp(var pre : array<TypedSymbol>&; t : DasType; f : SymFlags = SymFlags(0)) {
    pre |> push(make_sym("s{length(pre)}", t, f))
}

def outp(var post : array<TypedSymbol>&; pre : array<TypedSymbol>; t : DasType; f : SymFlags = SymFlags(0)) {
    post |> push(make_sym("s{length(pre) + length(post)}", t, f))
}

def add_brick(var pool : BrickPool&; code : string; var pre : array<TypedSymbol>&; var post : array<TypedSymbol>&; placement : BrickPlacement = BrickPlacement.IN_MAIN) {
    var brick : Brick
    brick.code = code
    brick.placement = placement
    brick.constraint.pre <- pre
    brick.constraint.post <- post
    pool.bricks |> emplace(brick)
}

// Initialize pool with arithmetic expression bricks
// Template markers: #s0#, #s1#, #s2# for symbols; #lit:int#, #lit:float# etc for literals
def init_arithmetic_bricks(var pool : BrickPool&) {
    let numeric_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tFloat, DasType.tDouble, DasType.tInt64, DasType.tUInt64)
    for (t in numeric_types) {
        let tn = type_name(t)
        // var sN : T = literal
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            outp(post, pre, t)
            add_brick(pool, "var #s0# : " + tn + " = #lit:" + tn + "#", pre, post)
        }
        // binary arith: var s2 = s0 op s1
        for (op in ARITH_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post)
        }
        // division: s0 / s1 where s1 is nonzero
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            inp(pre, t, SymFlags.nonzero)
            outp(post, pre, t)
            add_brick(pool, "var #s2# = #s0# / #s1#", pre, post)
        }
        // make nonzero: s1 = s0 != T(0) ? s0 : T(1)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            outp(post, pre, t, SymFlags.nonzero)
            if (t == DasType.tFloat) {
                add_brick(pool, "var #s1# = #s0# != 0.0 ? #s0# : 1.0", pre, post)
            } elif (t == DasType.tDouble) {
                add_brick(pool, "var #s1# = #s0# != 0.0lf ? #s0# : 1.0lf", pre, post)
            } elif (t == DasType.tUInt) {
                add_brick(pool, "var #s1# = #s0# != uint(0) ? #s0# : uint(1)", pre, post)
            } elif (t == DasType.tInt64) {
                add_brick(pool, "var #s1# = #s0# != int64(0) ? #s0# : int64(1)", pre, post)
            } elif (t == DasType.tUInt64) {
                add_brick(pool, "var #s1# = #s0# != uint64(0) ? #s0# : uint64(1)", pre, post)
            } else {
                add_brick(pool, "var #s1# = #s0# != 0 ? #s0# : 1", pre, post)
            }
        }
        // unary negate: var s1 = -s0
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool, "var #s1# = -#s0#", pre, post)
        }
        // comparison -> bool: var s2 = s0 op s1
        for (op in CMP_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            inp(pre, t)
            outp(post, pre, DasType.tBool)
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post)
        }
    }
    // Integer-only: bitwise ops
    let int_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tInt64, DasType.tUInt64)
    for (t in int_types) {
        for (op in BITWISE_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post)
        }
    }
    // Bool bricks
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s0# : bool = #lit:bool#", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tBool)
        inp(pre, DasType.tBool)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = #s0# && #s1#", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tBool)
        inp(pre, DasType.tBool)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = #s0# || #s1#", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tBool)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s1# = !#s0#", pre, post)
    }
    // Type conversions
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tFloat)
        add_brick(pool, "var #s1# = float(#s0#)", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tFloat)
        outp(post, pre, DasType.tInt)
        add_brick(pool, "var #s1# = int(#s0#)", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tDouble)
        add_brick(pool, "var #s1# = double(#s0#)", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt64)
        add_brick(pool, "var #s1# = int64(#s0#)", pre, post)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tUInt)
        add_brick(pool, "var #s1# = uint(#s0#)", pre, post)
    }
    // --- Strings ---
    init_string_bricks(pool)
    // --- For loops (bounded with range) ---
    init_for_loop_bricks(pool)
    // --- Functions ---
    init_function_bricks(pool)
    // --- If/elif/else ---
    init_if_bricks(pool)
    // --- Composite/heap constructs (dynamic arrays, fixed arrays, while) ---
    init_advanced_bricks(pool)
    // --- Runtime/system side-effect calls sprinkled at random points ---
    init_system_bricks(pool)
}

// Statement-only "system call" bricks: no inputs, no outputs (empty pre/post), so they are
// always candidates and get interleaved at random moments in the generated body. They emit
// runtime/system/debug side effects (GC, asserts, logging) that don't feed the data flow and
// don't perturb the interp/JIT stdout differential (to_log goes to the log, not stdout).
def add_stmt_brick(var pool : BrickPool&; code : string) {
    var pre : array<TypedSymbol>
    var post : array<TypedSymbol>
    add_brick(pool, code, pre, post)
}

def init_system_bricks(var pool : BrickPool&) {
    add_stmt_brick(pool, "unsafe \{ heap_collect() \}")          // force a GC pass
    add_stmt_brick(pool, "assert(true)")                         // assert codegen
    add_stmt_brick(pool, "verify(true)")                         // verify codegen
    add_stmt_brick(pool, "to_log(0, \"tick\\n\")")               // runtime logging (to log, not stdout)
    add_stmt_brick(pool, "unsafe \{ var _hb = heap_bytes_allocated(); to_log(0, \"\{_hb\}\") \}")
    add_stmt_brick(pool, "unsafe \{ var _sb = string_heap_bytes_allocated(); to_log(0, \"\{_sb\}\") \}")
}

// Dynamic array<int> / fixed_array iteration / while loops. All consume and produce
// `int`, so they slot into the scalar assembler unchanged. Each declares uniquely-named
// locals via the positional output marker (e.g. `#s2#_a` -> `v_N_a`) so multiple such
// bricks in one program never collide. These exercise heap allocation (GC), make-array
// codegen, iterator lowering, and the while/break codegen the scalar bricks never reach.
def init_advanced_bricks(var pool : BrickPool&) {
    // dynamic array: push twice, length -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_a : array<int>\n    #s2#_a |> push(#s0#)\n    #s2#_a |> push(#s1#)\n    var #s2# = length(#s2#_a)",
            pre, post)
    }
    // dynamic array: push, foreach accumulate -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_a : array<int>\n    #s2#_a |> push(#s0#)\n    #s2#_a |> push(#s1#)\n    #s2#_a |> push(#s0# + #s1#)\n    var #s2# = 0\n    for (#s2#_x in #s2#_a) \{\n        #s2# += #s2#_x\n    \}",
            pre, post)
    }
    // fixed_array foreach accumulate -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s3# = 0\n    for (#s3#_y in fixed_array(#s0#, #s1#, #s2#)) \{\n        #s3# += #s3#_y\n    \}",
            pre, post)
    }
    // while loop accumulate -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s1# = #s0#\n    var #s1#_i = 0\n    while (#s1#_i < 5) \{\n        #s1# += #s0#\n        #s1#_i ++\n    \}",
            pre, post)
    }
    // struct construct (named ctor) + field read -> int. Pair2 is defined in the
    // generated file header (see assembler). Exercises make-struct codegen + field access.
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_s = Pair2(a=#s0#, b=#s1#)\n    var #s2# = #s2#_s.a + #s2#_s.b",
            pre, post)
    }
    // struct default-init + field write/read -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_s : Pair2\n    #s2#_s.a = #s0#\n    #s2#_s.b = #s1#\n    var #s2# = #s2#_s.a * #s2#_s.b",
            pre, post)
    }
    // array<struct> push + foreach -> int (heap-allocated struct elements)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_a : array<Pair2>\n    #s2#_a |> push(Pair2(a=#s0#, b=#s1#))\n    #s2#_a |> push(Pair2(a=#s1#, b=#s0#))\n    var #s2# = 0\n    for (#s2#_p in #s2#_a) \{\n        #s2# += #s2#_p.a + #s2#_p.b\n    \}",
            pre, post)
    }
    // lambda (closure) + invoke -> int. Exercises lambda lowering + closure alloc.
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s1#_f = @@(#s1#_x : int) : int \{ return #s1#_x * 3 + 1; \}\n    var #s1# = invoke(#s1#_f, #s0#)",
            pre, post)
    }
    // table<int;int> insert + foreach keys/values -> int (managed heap container)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_t : table<int;int>\n    #s2#_t[#s0#] = #s1#\n    #s2#_t[#s1#] = #s0#\n    var #s2# = 0\n    for (#s2#_k, #s2#_v in keys(#s2#_t), values(#s2#_t)) \{\n        #s2# += #s2#_k + #s2#_v\n    \}",
            pre, post)
    }
    // tuple make + field access -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_t = (#s0#, #s1#)\n    var #s2# = #s2#_t._0 + #s2#_t._1",
            pre, post)
    }
    // array literal make ([ ... ]) + foreach -> int (the make-array codegen path)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_a <- [#s0#, #s1#, #s0# + #s1#]\n    var #s2# = 0\n    for (#s2#_x in #s2#_a) \{\n        #s2# += #s2#_x\n    \}",
            pre, post)
    }
    // int vector (int3) + swizzle -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s3#_v = int3(#s0#, #s1#, #s2#)\n    var #s3#_w = #s3#_v.zyx\n    var #s3# = #s3#_v.x + #s3#_v.y + #s3#_w.z",
            pre, post)
    }
    // float vector (float3) + length/dot -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s3#_v = float3(float(#s0#), float(#s1#), float(#s2#))\n    var #s3# = int(length(#s3#_v)) + int(dot(#s3#_v, #s3#_v))",
            pre, post)
    }
    // math builtins (abs/min/max/clamp) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2# = abs(#s0#) + min(#s0#, #s1#) + max(#s0#, #s1#) + clamp(#s0#, 0, 100)",
            pre, post)
    }
    // recursive function call (rec_sum defined in header) -> int; arg bounded to stay cheap
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s1# = rec_sum(abs(#s0#) % 12)",
            pre, post)
    }
    // generic function call (gmul defined in header) -> int; instantiates the int overload
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2# = gmul(#s0#, #s1#)",
            pre, post)
    }
    // enum value + int cast -> int (Col3 defined in header)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s1#_c = Col3.G\n    var #s1# = #s0# + int(#s1#_c)",
            pre, post)
    }
    // heap escape: mk_pair returns a `new` pointer that outlives its frame -> GC-tracked,
    // then force a collection. Exercises the managed-heap allocation + GC paths.
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_p = mk_pair(#s0#)\n    var #s2# = #s2#_p.a + #s2#_p.b + #s1#\n    unsafe \{ heap_collect() \}",
            pre, post)
    }
    // explicit new + delete -> int (heap alloc/free codegen)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2#_q = new Pair2\n    #s2#_q.a = #s0#\n    #s2#_q.b = #s1#\n    var #s2# = #s2#_q.a + #s2#_q.b\n    unsafe \{ delete #s2#_q \}",
            pre, post)
    }
    // generator function (gen_upto in header) + for-iterate -> int; arg bounded
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s1# = 0\n    for (#s1#_g in gen_upto(abs(#s0#) % 10)) \{\n        #s1# += #s1#_g\n    \}",
            pre, post)
    }
    // inline generator with capture + for-iterate -> int (generator desugar + heap iterator)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2# = 0\n    for (#s2#_y in generator<int>() <| $() \{ yield #s0#; yield #s1#; yield #s0# + #s1#; return false; \}) \{\n        #s2# += #s2#_y\n    \}",
            pre, post)
    }
}

def init_string_bricks(var pool : BrickPool&) {
    // String literal -> {s0: string}
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s0# = #lit:string#", pre, post)
    }
    // String concatenation: s0 + s1 -> s2
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s2# = #s0# + #s1#", pre, post)
    }
    // length(s0) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tInt)
        add_brick(pool, "var #s1# = length(#s0#)", pre, post)
    }
    // to_upper(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = to_upper(#s0#)", pre, post)
    }
    // to_lower(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = to_lower(#s0#)", pre, post)
    }
    // reverse(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = reverse(#s0#)", pre, post)
    }
    // slice(s0, 0, int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s2# = slice(#s0#, 0, #s1#)", pre, post)
    }
    // find(s0, s1) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tInt)
        add_brick(pool, "var #s2# = find(#s0#, #s1#)", pre, post)
    }
    // starts_with(s0, s1) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = starts_with(#s0#, #s1#)", pre, post)
    }
    // ends_with(s0, s1) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = ends_with(#s0#, #s1#)", pre, post)
    }
    // replace(s0, s1, s2) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s3# = replace(#s0#, #s1#, #s2#)", pre, post)
    }
    // strip(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = strip(#s0#)", pre, post)
    }
    // repeat(s0, int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = repeat(#s0#, 3)", pre, post)
    }
    // empty(s0) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s1# = empty(#s0#)", pre, post)
    }
    // s0 == s1 -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = #s0# == #s1#", pre, post)
    }
    // s0 != s1 -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = #s0# != #s1#", pre, post)
    }
    // character_at(s0, 0) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tInt)
        add_brick(pool, "var #s1# = character_at(#s0#, 0)", pre, post)
    }
    // to_char(int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = to_char(#s0#)", pre, post)
    }
    // int -> string via string builder
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = \"\{#s0#\}\"", pre, post)
    }
    // float -> string via string builder
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tFloat)
        outp(post, pre, DasType.tString)
        add_brick(pool, "var #s1# = \"\{#s0#\}\"", pre, post)
    }
    // contains(s0, s1) -> bool  (from strings_boost)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tString)
        inp(pre, DasType.tString)
        outp(post, pre, DasType.tBool)
        add_brick(pool, "var #s2# = contains(#s0#, #s1#)", pre, post)
    }
}

def init_for_loop_bricks(var pool : BrickPool&) {
    let numeric_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tFloat, DasType.tDouble, DasType.tInt64, DasType.tUInt64)
    for (t in numeric_types) {
        let tn = type_name(t)
        // for loop: accumulate sum   {s0: T} -> {s1: T}
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool,
                "var #s1# = #s0#\n    for (_ in range(10)) \{\n        #s1# = #s1# + #s0#\n    \}",
                pre, post)
        }
        // for loop: multiply
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool,
                "var #s1# = #s0#\n    for (_ in range(5)) \{\n        #s1# = #s1# * #s0#\n    \}",
                pre, post)
        }
    }
    // for loop with index variable exposed   {} -> {s0: int}
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s0# = 0\n    for (_i in range(10)) \{\n        #s0# += _i\n    \}",
            pre, post)
    }
    // for loop: count comparisons   {s0: T, s1: T} -> {s2: int}
    for (t in numeric_types) {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, t)
        inp(pre, t)
        outp(post, pre, DasType.tInt)
        add_brick(pool,
            "var #s2# = 0\n    for (_ in range(8)) \{\n        if (#s0# > #s1#) \{\n            #s2# ++\n        \}\n    \}",
            pre, post)
    }
}

def init_function_bricks(var pool : BrickPool&) {
    let numeric_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tFloat, DasType.tDouble, DasType.tInt64, DasType.tUInt64)
    for (t in numeric_types) {
        let tn = type_name(t)
        let f1t = func1_type_for(t)
        let f2t = func2_type_for(t)
        // Function: T -> T (double)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            outp(post, pre, f1t)
            add_brick(pool,
                "def #s0#(a : " + tn + ") : " + tn + " \{\n    return a + a\n\}",
                pre, post, BrickPlacement.TOP_LEVEL)
        }
        // Call 1-arg: f(s1) -> s2
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, f1t)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool, "var #s2# = #s0#(#s1#)", pre, post)
        }
        // Function: (T, T) -> T (add)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            outp(post, pre, f2t)
            add_brick(pool,
                "def #s0#(a : " + tn + "; b : " + tn + ") : " + tn + " \{\n    return a + b\n\}",
                pre, post, BrickPlacement.TOP_LEVEL)
        }
        // Call 2-arg: f(s1, s2) -> s3
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, f2t)
            inp(pre, t)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool, "var #s3# = #s0#(#s1#, #s2#)", pre, post)
        }
        // Function with for loop inside: T -> T
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            outp(post, pre, f1t)
            add_brick(pool,
                "def #s0#(a : " + tn + ") : " + tn + " \{\n    var r = a\n    for (_ in range(4)) \{\n        r = r + a\n    \}\n    return r\n\}",
                pre, post, BrickPlacement.TOP_LEVEL)
        }
    }
}

def init_if_bricks(var pool : BrickPool&) {
    let numeric_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tFloat, DasType.tDouble, DasType.tInt64, DasType.tUInt64)
    for (t in numeric_types) {
        let tn = type_name(t)
        // if (s0 > s1) { s2 = s0 } else { s2 = s1 }  (max)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, t)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool,
                "var #s2# : " + tn + "\n    if (#s0# > #s1#) \{\n        #s2# = #s0#\n    \} else \{\n        #s2# = #s1#\n    \}",
                pre, post)
        }
        // if (bool) { s1 = s0 + s0 } else { s1 = s0 }
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            inp(pre, DasType.tBool)
            inp(pre, t)
            outp(post, pre, t)
            add_brick(pool,
                "var #s2# = #s1#\n    if (#s0#) \{\n        #s2# = #s1# + #s1#\n    \}",
                pre, post)
        }
    }
    // if/elif chain producing bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        inp(pre, DasType.tInt)
        inp(pre, DasType.tInt)
        outp(post, pre, DasType.tBool)
        add_brick(pool,
            "var #s2# = false\n    if (#s0# > #s1#) \{\n        #s2# = true\n    \} elif (#s0# == #s1#) \{\n        #s2# = false\n    \} else \{\n        #s2# = true\n    \}",
            pre, post)
    }
}
