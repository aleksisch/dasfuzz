# Grammar based fuzzing

## Running

### Getting `Grammar-Mutator`
```
# Download antlr jar, required for Grammar-Mutator
wget https://www.antlr.org/download/antlr-4.8-complete.jar
cd ./modules/Grammar-Mutator
make GRAMMAR_FILE=../../type_inference_simple.json
```
Commands above will create `grammar_generator-type` and
`grammar_generator-type.so`

### Getting `AFLplusplus`
Simplest way is:
```
docker pull aflplusplus/aflplusplus:latest
docker run -ti -v $(pwd):/src aflplusplus/aflplusplus
```
building from sources will work as well.

### Building `daslang`
Daslang build expects 

AFL requires special binary built by `AFL` compiler:
```
cd /src/
cmake -Bbuild -DCMAKE_CXX_COMPILER=/AFLplusplus/afl-clang-fast++ -DCMAKE_C_COMPILER=/AFLplusplus/afl-clang-fast -GNinja -DCMAKE_BUILD_TYPE=Release -DDAS_GLFW_DISABLED=ON -DDAS_NO_ASSERTIONS=0
cmake --build build --target das_fuzz
```
This repository contains modified `main.cpp` for daslang `main`, main
change is that we created `AFL loop` in order to not reduce startup time by
avoiding rebuilding builtin modules.

### Running

AFL requires some seeds to be generated to begin with (1000 is number of seeds
and 200 is size limit, you can experiment with these numbers).
```
LD_LIBRARY_PATH=/src/modules/Grammar-Mutator/ /src/modules/Grammar-Mutator/grammar_generator-type 1000 200 ./seeds ./trees
```

All's good we are ready for fuzzing:
```
LD_LIBRARY_PATH=/src/modules/Grammar-Mutator/ TREES_PATH=./trees AFL_CUSTOM_MUTATOR_LIBRARY=/src/modules/Grammar-Mutator/libgrammarmutator-type.so AFL_CUSTOM_MUTATOR_ONLY=1 /AFLplusplus/afl-fuzz -i ./seeds -o ./out  -- /src/build/das_fuzz
```

We set output directory to `./out`, after running some time there will be:
- `default/crashes` - folder with all inputs that caused compiler crash
- `default/hangs` - folder with all inputs that caused compiler hung

Before submitting issue please run `afl-cmin` and `afl-tmin` on your input to minimize it:
```
/AFLplusplus/afl-cmin -C -i ./out/default/crashes/ -o ./corpus_min -- /src/build/das_fuzz
find ./out/default/crashes/ -name "id*" | xargs -I{} sh -c '/AFLplusplus/afl-tmin -i {} -o ./$(basename {}) -- /src/build/das_fuzz'
```

### Parallel fuzzing
Fuzzing requires a lot of resources, running in single thread is extremely
inefficient. AFL++ supports parallel fuzzing by running one main instance
and multiple secondary instances that share a single output directory.

Start the main fuzzer (`-M`):
```
LD_LIBRARY_PATH=/src/modules/Grammar-Mutator/ TREES_PATH=./trees AFL_CUSTOM_MUTATOR_LIBRARY=/src/modules/Grammar-Mutator/libgrammarmutator-type.so AFL_CUSTOM_MUTATOR_ONLY=1 /AFLplusplus/afl-fuzz -M fuzzer01 -i ./seeds -o ./out -- /src/build/das_fuzz
```

Start as many secondary fuzzers (`-S`) as you have spare cores:
```
LD_LIBRARY_PATH=/src/modules/Grammar-Mutator/ TREES_PATH=./trees AFL_CUSTOM_MUTATOR_LIBRARY=/src/modules/Grammar-Mutator/libgrammarmutator-type.so AFL_CUSTOM_MUTATOR_ONLY=1 /AFLplusplus/afl-fuzz -S fuzzer02 -i ./seeds -o ./out -- /src/build/das_fuzz
LD_LIBRARY_PATH=/src/modules/Grammar-Mutator/ TREES_PATH=./trees AFL_CUSTOM_MUTATOR_LIBRARY=/src/modules/Grammar-Mutator/libgrammarmutator-type.so AFL_CUSTOM_MUTATOR_ONLY=1 /AFLplusplus/afl-fuzz -S fuzzer03 -i ./seeds -o ./out -- /src/build/das_fuzz
```

All instances share the same `-o ./out` directory — each one creates its own
subdirectory (`out/fuzzer01/`, `out/fuzzer02/`, etc.) and periodically syncs
findings with the others.

Use `tmux` or `screen` to run each instance in a separate pane/window.
To check the status of all running instances at a glance:
```
/AFLplusplus/afl-whatsup ./out
```

See [AFL documentation](https://aflplus.plus/docs/parallel_fuzzing/) for more details.

## Grammar conversion
Daslang uses Bison. Many thanks to https://www.chrysalide.re/ for publishing
Python script for converting `Bison` grammar to `JSON` format used by `Grammar-Mutator`.
This script was slightly updated for `daslang`.

To convert grammar simply run:
```
python3 grammar_based/convert.py grammar.ypp > daslang_grammar.json
```

`convert.py` also injects UnitTest C++ binding non-terminals (types, enums,
hardcoded function calls) and applies a weight bias so the AFL Grammar-Mutator
picks them often enough to stress those bindings. Edit `UNIT_TEST_RULES` /
`BIAS` at the top of the script to tune what gets generated and how often;
re-run `convert.py` to regenerate the JSON (idempotent — running it twice
produces the same output).