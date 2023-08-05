# eruZero
Bullet-Train fast HashMap for Zig.

eruZero aims to be a replacement for Zig's standard library HashMap.

The motivation was to create a simple and fast map based on implicit data structure, which works well with any key from the start without providing context or a custom hasher. The only exceptions are .Float and untagged .Union. types. (*floats can be hashed, though. A convenient and fast key wrapper, breaking the float on integer and reminder parts with controlled precision, is present in the tests part of the code.*).

eruZero supports std/HashMap's main API. New features are dedicated update on an existing value, scaling down the underlying memory if no longer needed, basic operations on Sets, and tombstone automatic clean-up, making the map very resistant to the issue.

## Include in your project

for `build.zig.zon`

```zig
.{
    .name = "name_of_your_package",
    .version = "version_of_your_package",
    .dependencies = .{
        .eruZero = .{
            .url = "https://github.com/bogwi/eruzero/archive/master.tar.gz",
            .hash = "1220dbe03c05ad89578e952Ed3f2ff1fa611495f770773c711979ac00e48fd2825e9",
        },
    },
}

```
If the hash has changed, you will get a gentle  `error: hash mismatch` where in the field `found:` ZIG brings you the correct value.

for `build.zig`
 ```zig
    const eruZero = b.dependency("eruZero", .{});
    exe.addModule("eruZero", eruZero.module("eruZero"));
```

## Bench
Benchmark is inspired by https://github.com/xacrimon/dashmap, which has its benchmark ported of the libcuckoo benchmark.

There are four tests in total:

**RH: READ HEAVY**\
[read 98, insert 1,  remove 1,  update 0 ]\
Models caching of data in places such as web servers and disk page caches.

**EX: EXCHANGE**\
[read 10, insert 40, remove 40, update 10]\
Replicates a scenario where the map is used to exchange data.

**EXH: EXCHANGE HEAVY**\
[read 1, insert 98, remove 98, update 1]\
This test is an inverse of *RH* test. Hard for any map.

**RG: RAPID GROW**\
[read 5,  insert 80, remove 5,  update 10]\
A scenario where the map is used to gather large amounts of data under a short burst.

All tests save *RG* are designed to keep the map small. The keys are put on rotation, so the tests are tombstone-heavy. Especially *EXH* test. At the test's end, on the default 1M ops, the map has wrenched with 980k tombstones under the size of only 1! 

Benchmark against ZIG's HashMap can be invoked in the command line via

```
zig build bench
```
The default test runs on one million operations. You can run it on any number of ops; append the amount as `zig build bench -- 12345678`. It is ok to format the number as 12_345_678 with an underscore. Unintentionally, we can place too large a number, which might not be what we want.

## Performance and stats 

For each map, tests run as four independent loops by 100 ops each till the specified cap is reached. The results are interesting. Sure, a map like eruZero, which does not let deleted items accumulate, will have a tremendous advantage over the one with no such heuristic. As well it seems that building a hashmap backed by an underlying ArrayList is much more effective than talking to the allocator directly, at least in Zig's Universe. Further discussion is needed.

We have this on u64 keys, Wyhash for both maps, gpa allocator, ReleaseFast mode, and Apple M1 laptop. If you have build a hashmap that supports Zig's std:HashMap API and want it to be included in the benchmark, throw a word. You are very much welcome.

Tp: Throughput: millions of operations per second.\
Rt: Runtime   : time spent on the test, in seconds
 
```
                     HASHMAP BENCHMARK|
               1_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|std:HashMap                          |
|RH           |      54.72|   0.018275|
|EX           |      12.92|   0.077403|
|EXH          |       4.18|   0.239329|
|RG           |      54.31|   0.018413|

|eruZero                              |
|RH           |     262.36|   0.003812|
|EX           |      51.70|   0.019342|
|EXH          |      25.26|   0.039586|
|RG           |      50.91|   0.019644|


                     HASHMAP BENCHMARK|
              10_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|std:HashMap                          |
|RH           |      62.77|   0.159300|
|EX           |      13.12|   0.762084|
|EXH          |       4.17|   2.399021|
|RG           |      37.10|   0.269574|

|eruZero                              |
|RH           |     254.29|   0.039326|
|EX           |      53.59|   0.186602|
|EXH          |      24.47|   0.408668|
|RG           |      40.26|   0.248383|


                     HASHMAP BENCHMARK|
             100_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|std:HashMap                          |
|RH           |      62.37|   1.603271|
|EX           |      13.15|   7.605165|
|EXH          |       4.18|  23.929449|
|RG           |      24.91|   4.013939|

|eruZero                              |
|RH           |     259.40|   0.385501|
|EX           |      54.57|   1.832400|
|EXH          |      24.65|   4.057070|
|RG           |      35.20|   2.840792|

```


