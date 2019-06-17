# Preallocator.jl

Provides a macro which gives (potentially) big speedups for some memory-bound computations. 

## Usage

Suppose you have some memory-bound calculation inside of a loop, 

```julia
for i=1:N
    foo()
end
```

where `foo()` is a function which spends significant time in garbage collection, e.g. because it allocates and destroys lots of temporary arrays. 

With this package you can write:


```julia
using Preallocator

mem = @preallocate foo()

for i=1:N
    @preallocated mem foo()
end
```

The `mem = @preallocate foo()` line calls your function `foo()`, tracks every allocation made from within this code, and returns and saves this memory in `mem`. The `@preallocated mem foo()` line then calls your function like before but every allocation made is now replaced with simply reusing the same memory from `mem`, avoiding unnecessary reallocations and garbage collection. 

Both `@preallocated` and `@preallocate` leave your code type-stable.

## Example

Non-broadcasted algebra over vectors allocates temporary arrays for every binary operation. We can get rid of this memory overhead by preallocating these temporary arrays once. 

```julia

using Preallocator
using BenchmarkTools

v1, v2, v3 = rand(128^2), rand(128^2), rand(128^2)

# no broadcasting, no pre-allocation
bar(v1,v2,v3) = v1 + (v2 + v3)
@btime bar($v1,$v2,$v3);       # 26.452 μs (4 allocations: 256.16 KiB)

# no broadcasting, with preallocation
mem = @preallocate v1 + (v2 + v3)
foo(mem,v1,v2,v3) = @preallocated mem v1 + (v2 + v3)
@btime foo($mem,$v1,$v2,$v3);  # 12.500 μs (4 allocations: 176 bytes)

# with broadcasting
baz(v1,v2,v3) = @. v1 + v2 + v3
@btime baz($v1,$v2,$v3);       # 12.851 μs (3 allocations: 128.11 KiB)


```

Of course, in this toy example one should just use broadcasting, but Preallocator.jl lets you achieve comparable speeds even in cases where its not easy or possible to do so. 


## Caveats

* This only works for deterministic code, i.e. where exactly the same memory is allocated in the same order each time you call your function `foo()`. 
* Currently only `Array` allocations are tracked.
* This is not currently threadsafe (i.e., multiple threads can't use the same `mem`)
