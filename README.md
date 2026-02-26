# dasfuzz

## Grammar based

Currently we support only Grammar-Based fuzzing.

### How it works
- Daslang has a grammar in bison format
- This grammar can be converted to JSON and slightly modified to help [GrammarMutator](https://github.com/AFLplusplus/Grammar-Mutator)
- Grammar mutator generates test corpuses by input grammar
- [AFLplusplus](https://github.com/AFLplusplus/AFLplusplus) fuzzer support
custom mutations which makes all the inputs at least pass parser phase.

More info about usage of `Grammar-Based` fuzzing of `DaScript` can be found at [README](grammar_based/README.md)

## Custom approach
Note that:
- Using pure AFL is ideal for fuzzing parser phase (we use bison/flex for it, so we're not interested)
- Using GrammarMutator let us pass parsing phase, and concentrate on type checking

Which means for testing runtime we had to change approach (or significantly change grammar)
to generate valid programs more regularly that will always pass type checker.