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
    num_symbols : int
}

// The pool of all available bricks
struct BrickPool {
    bricks : array<Brick>
}

def type_name(t : DasType) : string {
    if (t == DasType.tInt) {
        return "int"
    } elif (t == DasType.tUInt) {
        return "uint"
    } elif (t == DasType.tFloat) {
        return "float"
    } elif (t == DasType.tDouble) {
        return "double"
    } elif (t == DasType.tInt64) {
        return "int64"
    } elif (t == DasType.tUInt64) {
        return "uint64"
    } elif (t == DasType.tBool) {
        return "bool"
    } elif (t == DasType.tString) {
        return "string"
    }
    return "int"
}

def random_literal(t : DasType) : string {
    if (t == DasType.tInt) {
        return "{random_int(rng_seed) - 2}"
    } elif (t == DasType.tUInt) {
        return "uint({random_int(rng_seed)})"
    } elif (t == DasType.tFloat) {
        return "{random_float(rng_seed)}"
    } elif (t == DasType.tDouble) {
        return "{random_float(rng_seed)}lf"
    } elif (t == DasType.tInt64) {
        return "int64({random_int(rng_seed) - 2})"
    } elif (t == DasType.tUInt64) {
        return "uint64({random_int(rng_seed)})"
    } elif (t == DasType.tBool) {
        return random_int(rng_seed) > 0 ? "true" : "false"
    } elif (t == DasType.tString) {
        let strs = fixed_array("hello", "world", "foo", "bar", "test", " ", "abc", "123", "Hello World", "")
        return "\"" + strs[random_int(rng_seed) % length(strs)] + "\""
    }
    return "0"
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

def make_sym_nz(n : string; t : DasType) : TypedSymbol {
    return make_sym(n, t, SymFlags.nonzero)
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

def add_brick(var pool : BrickPool&; code : string; var pre : array<TypedSymbol>&; var post : array<TypedSymbol>&; num_sym : int; placement : BrickPlacement = BrickPlacement.IN_MAIN) {
    var brick : Brick
    brick.code = code
    brick.placement = placement
    brick.constraint.pre <- pre
    brick.constraint.post <- post
    brick.num_symbols = num_sym
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
            post |> push(make_sym("s0", t))
            add_brick(pool, "var #s0# : " + tn + " = #lit:" + tn + "#", pre, post, 1)
        }
        // binary arith: var s2 = s0 op s1
        for (op in ARITH_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post, 3)
        }
        // division: s0 / s1 where s1 is nonzero
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            pre |> push(make_sym_nz("s1", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym_nz("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool, "var #s2# = #s0# / #s1#", pre, post, 3)
        }
        // make nonzero: s1 = s0 != T(0) ? s0 : T(1)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym_nz("s1", t))
            if (t == DasType.tFloat) {
                add_brick(pool, "var #s1# = #s0# != 0.0 ? #s0# : 1.0", pre, post, 2)
            } elif (t == DasType.tDouble) {
                add_brick(pool, "var #s1# = #s0# != 0.0lf ? #s0# : 1.0lf", pre, post, 2)
            } elif (t == DasType.tUInt) {
                add_brick(pool, "var #s1# = #s0# != uint(0) ? #s0# : uint(1)", pre, post, 2)
            } elif (t == DasType.tInt64) {
                add_brick(pool, "var #s1# = #s0# != int64(0) ? #s0# : int64(1)", pre, post, 2)
            } elif (t == DasType.tUInt64) {
                add_brick(pool, "var #s1# = #s0# != uint64(0) ? #s0# : uint64(1)", pre, post, 2)
            } else {
                add_brick(pool, "var #s1# = #s0# != 0 ? #s0# : 1", pre, post, 2)
            }
        }
        // unary negate: var s1 = -s0
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            add_brick(pool, "var #s1# = -#s0#", pre, post, 2)
        }
        // comparison -> bool: var s2 = s0 op s1
        for (op in CMP_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", DasType.tBool))
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post, 3)
        }
    }
    // Integer-only: bitwise ops
    let int_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tInt64, DasType.tUInt64)
    for (t in int_types) {
        for (op in BITWISE_OPS) {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool, "var #s2# = #s0# " + op + " #s1#", pre, post, 3)
        }
    }
    // Bool bricks
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        post |> push(make_sym("s0", DasType.tBool))
        add_brick(pool, "var #s0# : bool = #lit:bool#", pre, post, 1)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tBool))
        pre |> push(make_sym("s1", DasType.tBool))
        post |> push(make_sym("s0", DasType.tBool))
        post |> push(make_sym("s1", DasType.tBool))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = #s0# && #s1#", pre, post, 3)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tBool))
        pre |> push(make_sym("s1", DasType.tBool))
        post |> push(make_sym("s0", DasType.tBool))
        post |> push(make_sym("s1", DasType.tBool))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = #s0# || #s1#", pre, post, 3)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tBool))
        post |> push(make_sym("s0", DasType.tBool))
        post |> push(make_sym("s1", DasType.tBool))
        add_brick(pool, "var #s1# = !#s0#", pre, post, 2)
    }
    // Type conversions
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tFloat))
        add_brick(pool, "var #s1# = float(#s0#)", pre, post, 2)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tFloat))
        post |> push(make_sym("s0", DasType.tFloat))
        post |> push(make_sym("s1", DasType.tInt))
        add_brick(pool, "var #s1# = int(#s0#)", pre, post, 2)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tDouble))
        add_brick(pool, "var #s1# = double(#s0#)", pre, post, 2)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tInt64))
        add_brick(pool, "var #s1# = int64(#s0#)", pre, post, 2)
    }
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tUInt))
        add_brick(pool, "var #s1# = uint(#s0#)", pre, post, 2)
    }
    // --- Strings ---
    init_string_bricks(pool)
    // --- For loops (bounded with range) ---
    init_for_loop_bricks(pool)
    // --- Functions ---
    init_function_bricks(pool)
    // --- If/elif/else ---
    init_if_bricks(pool)
}

def init_string_bricks(var pool : BrickPool&) {
    // String literal
    // Pre: {} -> Post: {s0: string}
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        post |> push(make_sym("s0", DasType.tString))
        add_brick(pool, "var #s0# = #lit:string#", pre, post, 1)
    }
    // String concatenation: s0 + s1 -> s2
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tString))
        add_brick(pool, "var #s2# = #s0# + #s1#", pre, post, 3)
    }
    // length(s0) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tInt))
        add_brick(pool, "var #s1# = length(#s0#)", pre, post, 2)
    }
    // to_upper(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = to_upper(#s0#)", pre, post, 2)
    }
    // to_lower(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = to_lower(#s0#)", pre, post, 2)
    }
    // reverse(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = reverse(#s0#)", pre, post, 2)
    }
    // slice(s0, 0, int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tInt))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tInt))
        post |> push(make_sym("s2", DasType.tString))
        add_brick(pool, "var #s2# = slice(#s0#, 0, #s1#)", pre, post, 3)
    }
    // find(s0, s1) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tInt))
        add_brick(pool, "var #s2# = find(#s0#, #s1#)", pre, post, 3)
    }
    // starts_with(s0, s1) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = starts_with(#s0#, #s1#)", pre, post, 3)
    }
    // ends_with(s0, s1) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = ends_with(#s0#, #s1#)", pre, post, 3)
    }
    // replace(s0, s1, s2) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        pre |> push(make_sym("s2", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tString))
        post |> push(make_sym("s3", DasType.tString))
        add_brick(pool, "var #s3# = replace(#s0#, #s1#, #s2#)", pre, post, 4)
    }
    // strip(s0) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = strip(#s0#)", pre, post, 2)
    }
    // repeat(s0, int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = repeat(#s0#, 3)", pre, post, 2)
    }
    // empty(s0) -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tBool))
        add_brick(pool, "var #s1# = empty(#s0#)", pre, post, 2)
    }
    // s0 == s1 -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = #s0# == #s1#", pre, post, 3)
    }
    // s0 != s1 -> bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = #s0# != #s1#", pre, post, 3)
    }
    // character_at(s0, 0) -> int
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tInt))
        add_brick(pool, "var #s1# = character_at(#s0#, 0)", pre, post, 2)
    }
    // to_char(int) -> string
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = to_char(#s0#)", pre, post, 2)
    }
    // int -> string via string builder
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = \"\{#s0#\}\"", pre, post, 2)
    }
    // float -> string via string builder
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tFloat))
        post |> push(make_sym("s0", DasType.tFloat))
        post |> push(make_sym("s1", DasType.tString))
        add_brick(pool, "var #s1# = \"\{#s0#\}\"", pre, post, 2)
    }
    // contains(s0, s1) -> bool  (from strings_boost)
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tString))
        pre |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s0", DasType.tString))
        post |> push(make_sym("s1", DasType.tString))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool, "var #s2# = contains(#s0#, #s1#)", pre, post, 3)
    }
}

def init_for_loop_bricks(var pool : BrickPool&) {
    let numeric_types = fixed_array(DasType.tInt, DasType.tUInt, DasType.tFloat, DasType.tDouble, DasType.tInt64, DasType.tUInt64)
    for (t in numeric_types) {
        let tn = type_name(t)
        // for loop: accumulate sum
        // Pre: {s0: T} -> Post: {s0: T, s1: T}
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            add_brick(pool,
                "var #s1# = #s0#\n    for (_ in range(10)) \{\n        #s1# = #s1# + #s0#\n    \}",
                pre, post, 2)
        }
        // for loop: multiply
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            add_brick(pool,
                "var #s1# = #s0#\n    for (_ in range(5)) \{\n        #s1# = #s1# * #s0#\n    \}",
                pre, post, 2)
        }
    }
    // for loop with index variable exposed
    // Pre: {} -> Post: {s0: int}
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        post |> push(make_sym("s0", DasType.tInt))
        add_brick(pool,
            "var #s0# = 0\n    for (_i in range(10)) \{\n        #s0# += _i\n    \}",
            pre, post, 1)
    }
    // for loop: count comparisons -> int
    // Pre: {s0: T, s1: T} -> Post: {s0: T, s1: T, s2: int}
    for (t in numeric_types) {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", t))
        pre |> push(make_sym("s1", t))
        post |> push(make_sym("s0", t))
        post |> push(make_sym("s1", t))
        post |> push(make_sym("s2", DasType.tInt))
        add_brick(pool,
            "var #s2# = 0\n    for (_ in range(8)) \{\n        if (#s0# > #s1#) \{\n            #s2# ++\n        \}\n    \}",
            pre, post, 3)
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
            post |> push(make_sym("s0", f1t))
            add_brick(pool,
                "def #s0#(a : " + tn + ") : " + tn + " \{\n    return a + a\n\}",
                pre, post, 1, BrickPlacement.TOP_LEVEL)
        }
        // Call 1-arg: f(s1) -> s2
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", f1t))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", f1t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool, "var #s2# = #s0#(#s1#)", pre, post, 3)
        }
        // Function: (T, T) -> T (add)
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            post |> push(make_sym("s0", f2t))
            add_brick(pool,
                "def #s0#(a : " + tn + "; b : " + tn + ") : " + tn + " \{\n    return a + b\n\}",
                pre, post, 1, BrickPlacement.TOP_LEVEL)
        }
        // Call 2-arg: f(s1, s2) -> s3
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", f2t))
            pre |> push(make_sym("s1", t))
            pre |> push(make_sym("s2", t))
            post |> push(make_sym("s0", f2t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            post |> push(make_sym("s3", t))
            add_brick(pool, "var #s3# = #s0#(#s1#, #s2#)", pre, post, 4)
        }
        // Function with for loop inside: T -> T
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            post |> push(make_sym("s0", f1t))
            add_brick(pool,
                "def #s0#(a : " + tn + ") : " + tn + " \{\n    var r = a\n    for (_ in range(4)) \{\n        r = r + a\n    \}\n    return r\n\}",
                pre, post, 1, BrickPlacement.TOP_LEVEL)
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
            pre |> push(make_sym("s0", t))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", t))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool,
                "var #s2# : " + tn + "\n    if (#s0# > #s1#) \{\n        #s2# = #s0#\n    \} else \{\n        #s2# = #s1#\n    \}",
                pre, post, 3)
        }
        // if (bool) { s1 = s0 + s0 } else { s1 = s0 }
        {
            var pre : array<TypedSymbol>
            var post : array<TypedSymbol>
            pre |> push(make_sym("s0", DasType.tBool))
            pre |> push(make_sym("s1", t))
            post |> push(make_sym("s0", DasType.tBool))
            post |> push(make_sym("s1", t))
            post |> push(make_sym("s2", t))
            add_brick(pool,
                "var #s2# = #s1#\n    if (#s0#) \{\n        #s2# = #s1# + #s1#\n    \}",
                pre, post, 3)
        }
    }
    // if/elif chain producing bool
    {
        var pre : array<TypedSymbol>
        var post : array<TypedSymbol>
        pre |> push(make_sym("s0", DasType.tInt))
        pre |> push(make_sym("s1", DasType.tInt))
        post |> push(make_sym("s0", DasType.tInt))
        post |> push(make_sym("s1", DasType.tInt))
        post |> push(make_sym("s2", DasType.tBool))
        add_brick(pool,
            "var #s2# = false\n    if (#s0# > #s1#) \{\n        #s2# = true\n    \} elif (#s0# == #s1#) \{\n        #s2# = false\n    \} else \{\n        #s2# = true\n    \}",
            pre, post, 3)
    }
}
