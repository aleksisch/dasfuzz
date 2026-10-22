/* Zig's sancov pass emits a reference to the stack-depth tracker that the full
   sanitizer runtime owns. AFL++'s afl-compiler-rt.o does not define it and
   nothing in an AFL build reads it, so an empty definition is enough to link. */
__thread unsigned long __sancov_lowest_stack;
