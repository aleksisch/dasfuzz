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
cmake -Bbuild -DDAS_ -DCMAKE_CXX_COMPILER=/AFLplusplus/afl-clang-fast++ -DCMAKE_C_COMPILER=/AFLplusplus/afl-clang-fast -GNinja -DCMAKE_BUILD_TYPE=Debug -DDAS_GLFW_DISABLED=ON
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

Before submitting issue please run `afl-tmin` on your input to minimize it:
```
find ./out/default/crashes/ -name "id*" | xargs -I{} sh -c '/AFLplusplus/afl-tmin -i {} -o ./$(basename {}) -- /src/build/das_fuzz'
```

### Parallel fuzzing
Fuzzing requires a lot of resources, running in single thread is extremely
inefficient. There is no `single-command` to make all the above parallel.
See [AFL documentation](https://aflplus.plus/docs/parallel_fuzzing/) on how to run on multiple threads.

## Grammar conversion
Daslang uses Bison. Many thanks to https://www.chrysalide.re/ for publishing
Python script for converting `Bison` grammar to `JSON` format used by `Grammar-Mutator`.
This script was slightly updated for `daslang`.

To convert grammar simply run:
```
python3 grammar_based/convert.py grammar.ypp > daslang_grammar.json
```