test { const e: error{A,B}!u32 = error.A; e catch |err| switch (err) { error.B => {}, error.A => |foo, tag| { _ = foo; _ = tag; }, }; }
