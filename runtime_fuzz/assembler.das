options gen2
module assembler shared

require daslib/strings_boost
require daslib/random

require bricks

// Current assembly state: tracks all defined symbols
struct AssemblyState {
    symbols : array<TypedSymbol>
    var_counter : int
    func_counter : int
}

def is_func_type(t : DasType) : bool {
    return t == DasType.tFunc1Int || t == DasType.tFunc1UInt || t == DasType.tFunc1Float || t == DasType.tFunc1Double || t == DasType.tFunc1Int64 || t == DasType.tFunc1UInt64 || t == DasType.tFunc2Int || t == DasType.tFunc2UInt || t == DasType.tFunc2Float || t == DasType.tFunc2Double || t == DasType.tFunc2Int64 || t == DasType.tFunc2UInt64
}

def can_use_brick(state : AssemblyState; brick : Brick) : bool {
    for (pre_sym in brick.constraint.pre) {
        var found = false
        for (s in state.symbols) {
            if (sym_matches(s, pre_sym)) {
                found = true
                break
            }
        }
        if (!found) {
            return false
        }
    }
    return true
}

def pick_symbol(state : AssemblyState; required : TypedSymbol) : string {
    var candidates : array<string>
    for (sym in state.symbols) {
        if (sym_matches(sym, required)) {
            candidates |> push(sym.name)
        }
    }
    if (length(candidates) == 0) {
        return ""
    }
    return candidates[random_int(rng_seed) % length(candidates)]
}

// Instantiate a brick template: replace #s0#, #s1#, ... with actual variable names
// and #lit:TYPE# with random literals
def instantiate_brick(brick : Brick; state : AssemblyState) : string {
    var result = brick.code
    var mapping : table<string; string>
    for (pre_sym in brick.constraint.pre) {
        if (!key_exists(mapping, pre_sym.name)) {
            mapping[pre_sym.name] = pick_symbol(state, pre_sym)
        }
    }
    var new_var_idx = state.var_counter
    var new_func_idx = state.func_counter
    for (post_sym in brick.constraint.post) {
        if (!key_exists(mapping, post_sym.name)) {
            var is_in_pre = false
            for (pre_sym in brick.constraint.pre) {
                if (pre_sym.name == post_sym.name) {
                    is_in_pre = true
                    break
                }
            }
            if (!is_in_pre) {
                if (is_func_type(post_sym.sym_type)) {
                    mapping[post_sym.name] = "fn_{new_func_idx}"
                    new_func_idx++
                } else {
                    mapping[post_sym.name] = "v_{new_var_idx}"
                    new_var_idx++
                }
            }
        }
    }
    // Replace #sN# with mapped names
    for (key, val in keys(mapping), values(mapping)) {
        result = result |> replace("#" + key + "#", val)
    }
    // Replace #lit:TYPE# with random literals
    result = result |> replace("#lit:int#", random_literal(DasType.tInt))
    result = result |> replace("#lit:uint#", random_literal(DasType.tUInt))
    result = result |> replace("#lit:float#", random_literal(DasType.tFloat))
    result = result |> replace("#lit:double#", random_literal(DasType.tDouble))
    result = result |> replace("#lit:int64#", random_literal(DasType.tInt64))
    result = result |> replace("#lit:uint64#", random_literal(DasType.tUInt64))
    result = result |> replace("#lit:bool#", random_literal(DasType.tBool))
    result = result |> replace("#lit:string#", random_literal(DasType.tString))
    return result
}

def hash_cast(name : string; t : DasType) : string {
    if (t == DasType.tInt) {
        return name
    } elif (t == DasType.tUInt) {
        return "int(" + name + ")"
    } elif (t == DasType.tFloat) {
        return "int(" + name + ")"
    } elif (t == DasType.tDouble) {
        return "int(" + name + ")"
    } elif (t == DasType.tInt64) {
        return "int(" + name + ")"
    } elif (t == DasType.tUInt64) {
        return "int(" + name + ")"
    } elif (t == DasType.tBool) {
        return "(" + name + " ? 1 : 0)"
    } elif (t == DasType.tString) {
        return "length(" + name + ")"
    }
    return "0"
}

def assemble(pool : BrickPool; i_max : int; p_blk : float) : string {
    var state : AssemblyState
    var top_lines : array<string>
    var main_lines : array<string>
    var func_counter = 0
    for (i in range(i_max)) {
        var candidates : array<int>
        for (idx in range(length(pool.bricks))) {
            if (can_use_brick(state, pool.bricks[idx])) {
                candidates |> push(idx)
            }
        }
        if (length(candidates) == 0) {
            break
        }
        let chosen_idx = candidates[random_int(rng_seed) % length(candidates)]
        let line = instantiate_brick(pool.bricks[chosen_idx], state)
        let brick & = unsafe(pool.bricks[chosen_idx])
        if (brick.placement == BrickPlacement.TOP_LEVEL) {
            top_lines |> push(line)
        } else {
            main_lines |> push("    " + line)
        }
        // Update state: add new symbols from postcondition
        for (post_sym in brick.constraint.post) {
            var is_in_pre = false
            for (pre_sym in brick.constraint.pre) {
                if (pre_sym.name == post_sym.name) {
                    is_in_pre = true
                    break
                }
            }
            if (!is_in_pre) {
                if (is_func_type(post_sym.sym_type)) {
                    state.symbols |> push(make_sym("fn_{state.func_counter}", post_sym.sym_type, post_sym.flags))
                    state.func_counter++
                } else {
                    state.symbols |> push(make_sym("v_{state.var_counter}", post_sym.sym_type, post_sym.flags))
                    state.var_counter++
                }
            }
        }
    }
    // Build hash lines from all non-function symbols
    var hash_lines : array<string>
    hash_lines |> push("    var _hash = 0")
    for (sym in state.symbols) {
        if (!is_func_type(sym.sym_type)) {
            let hashed = hash_cast(sym.name, sym.sym_type)
            hash_lines |> push("    _hash = _hash ^ " + hashed)
        }
    }
    hash_lines |> push("    print(\"\{_hash\}\\n\")")
    return build_string() <| $(var writer) {
        writer |> write("options gen2\noptions gc\n\nrequire strings\nrequire daslib/strings_boost\nrequire math\n\n")
        // Standard helpers referenced by advanced bricks: a struct, a bounded recursive
        // function, a generic (untyped-arg) function, an enum, a heap-escaping allocator
        // (returns a `new` pointer that outlives its frame -> GC-managed), and a generator.
        writer |> write("struct Pair2 \{ a : int; b : int \}\n")
        writer |> write("def rec_sum(n : int) : int \{ if (n <= 0) \{ return 0 \}; return n + rec_sum(n - 1) \}\n")
        writer |> write("def gmul(a, b) \{ return a * b \}\n")
        writer |> write("enum Col3 \{ R, G, B \}\n")
        writer |> write("def mk_pair(v : int) \{ var p = new Pair2; p.a = v; p.b = v * 2; return p \}\n")
        writer |> write("def gen_upto(n : int) : iterator<int> \{ return generator<int>() <| $() \{ for (i in range(n)) \{ yield i \}; return false; \} \}\n\n")
        for (line in top_lines) {
            writer |> write(line)
            writer |> write("\n\n")
        }
        writer |> write("[export]\n")
        writer |> write("def main() \{\n")
        for (line in main_lines) {
            writer |> write(line)
            writer |> write("\n")
        }
        for (line in hash_lines) {
            writer |> write(line)
            writer |> write("\n")
        }
        writer |> write("\}\n")
    }
}
