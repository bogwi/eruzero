# eruZero
Bullet-Train fast hashmap for Zig.

eruZero aims to be a replacement for Zig's standard HashMap.

The motivation was to create a simple and fast map based on an implicit data structure that works well with any key out of the box, without providing context or a custom hasher. The only exceptions are .Float and untagged .Union types. *(Floats can be hashed, though. A convenient and fast key wrapper that breaks the float on integer and memo parts with controlled precision is present in the tests part of the code.)*

eruZero supports the main std/HashMap API. New features are dedicated update to an existing value, scaling down the underlying memory when no longer needed, basic operations on sets, and automatic tombstone cleanup, making the map very resistant to the problem.

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
A scenario where the map is used to collect large amounts of data in a short burst.

All tests except *RG* are designed to keep the map small. The keys are rotated, so the tests are tombstone-heavy. Especially the *EXH* test. At the end of the test, on the default 1M ops, the map has wrenched with 980k tombstones under the size of only 1! 

Benchmark against ZIG's both HashMap and ArrayHashMap can be called in the command line via

```
zig build bench
```
The default test runs on one million ops. You can run it with any number of operations; append the number as `zig build bench -- 12345678`. It is okay to format the number as 12_345_678 with an underscore. Unintentionally, we can make the number too large, which may not be what we want.

## Performance and stats 

For each card, the tests are run as four independent loops of 100 ops each until the specified cap is reached. The results are interesting. Sure, a map like eruZero, which does not let deleted items accumulate, will have a huge advantage over the one without such a heuristic. Also, it seems that building a hashmap backed by an underlying ArrayList is much more effective than talking directly to the allocator, at least in Zig's universe. Further discussion is needed.

We did this on u64 keys, wyhash for both maps, gpa allocator, ReleaseFast mode, and Apple M1 laptop. If you have built a hashmap that supports Zig's std:HashMap API and would like to see it included in the benchmark, drop us a line. You are very welcome.

*Tp*: Throughput: millions of operations per second.\
*Rt*: Runtime   : time spent on the test, in seconds.\
*aggregate*: This is an absolute measurement of an individual hashmap's *throughput* (total number of ops the map has engaged through the four tests in a row divided by the combined *runtime*) contrary to single tests measuring relative performances.
 
```
                     HASHMAP BENCHMARK|
               1_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|eruZero                              |
|RH           |     251.46|   0.003977|
|EX           |      63.16|   0.015832|
|EXH          |      64.25|   0.015563|
|RG           |      47.46|   0.021070|
|aggregate    |      70.87|   0.056442|

|ArrayHashMap                         |
|RH           |     139.60|   0.007163|
|EX           |      81.52|   0.012268|
|EXH          |      81.63|   0.012250|
|RG           |      24.66|   0.040544|
|aggregate    |      55.38|   0.072225|

|HashMap                              |
|RH           |      62.65|   0.015961|
|EX           |      13.04|   0.076673|
|EXH          |       8.28|   0.120821|
|RG           |      57.06|   0.017524|
|aggregate    |      17.32|   0.230980|


                     HASHMAP BENCHMARK|
              10_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|eruZero                              |
|RH           |     256.21|   0.039030|
|EX           |      62.19|   0.160800|
|EXH          |      59.97|   0.166756|
|RG           |      36.06|   0.277308|
|aggregate    |      62.12|   0.643895|

|ArrayHashMap                         |
|RH           |     141.78|   0.070530|
|EX           |      84.29|   0.118637|
|EXH          |      83.80|   0.119330|
|RG           |      17.61|   0.567956|
|aggregate    |      45.64|   0.876454|

|HashMap                              |
|RH           |      64.22|   0.155703|
|EX           |      13.20|   0.757729|
|EXH          |       8.34|   1.199348|
|RG           |      36.86|   0.271328|
|aggregate    |      16.78|   2.384107|


                     HASHMAP BENCHMARK|
             100_000_000 ops:each test|

|name         |Tp Mops:sec|    Rt :sec|
 =====================================
|eruZero                              |
|RH           |     258.13|   0.387407|
|EX           |      65.79|   1.520057|
|EXH          |      62.78|   1.592761|
|RG           |      26.91|   3.715796|
|aggregate    |      55.43|   7.216020|

|ArrayHashMap                         |
|RH           |     144.43|   0.692390|
|EX           |      86.05|   1.162134|
|EXH          |      84.47|   1.183876|
|RG           |      17.79|   5.621304|
|aggregate    |      46.19|   8.659705|

|HashMap                              |
|RH           |      64.08|   1.560445|
|EX           |      13.21|   7.567642|
|EXH          |       8.34|  11.988912|
|RG           |      25.86|   3.867002|
|aggregate    |      16.01|  24.984001|

```

## Conclusions
Based on the above data, if you are building an application that is *READ HEAVY*, consider using the eruZero map, which is specifically designed for static reading with occasional removals. If you are building an application similar to the *EXCHANGE* test, consider using ArrayHashMap, which has excellent removal performance and almost instant iteration over the entire map (not tested here). Zig's HashMap is great for growing and reading small volumes under 1M entries. In general, eruZero completed four tests in the least amount of time.

If you do not want external dependencies, you should still consider using Zig's excellent ArrayHashMap in your projects, which is an overall better alternative to Zig's HashMap. ArrayHashMap is somewhat underestimated in Zig's community (as it seems, scavenging the GitHub data) because it grows slower than std:HashMap and because of popular synthetic tests, usually consisting of *grow-clear-put_again-get-iterate-remove* sequence or similar, used to benchmark hashmaps. And somehow it got into people's heads that the map that runs the sequence faster is better. In fact, the ArrayHashMap will not come out on top in such synthetic tests. However, tests that do not measure the hashmap's performance by the number of deleted entries it holds at runtime cannot tell the whole truth.


