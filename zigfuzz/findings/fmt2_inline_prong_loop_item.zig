test {
    switch (@as(u8, 0)) {
        0 => {},
        inline for (.{}) |_| 0 => {},
        else => {},
    }
}
