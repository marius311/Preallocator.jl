using Preallocator
using BenchmarkTools

v1, v2, v3 = rand(128^2), rand(128^2), rand(128^2);
result = similar(v1)


foo(mem,v1,v2,v3) = @usemem mem result = v1 + (v2 + v3)
bar(v1,v2,v3) = result = v1 + (v2 + v3)
baz(v1,v2,v3) = @. result = v1 + v2 + v3

mem = @preallocate v1 + (v2 + v3)

@btime foo($mem,$v1,$v2,$v3);
@btime bar($v1,$v2,$v3);
@btime baz($v1,$v2,$v3);

@time foo(mem,v1,v2,v3)
@time bar(v1,v2,v3)

@code_warntype foo(mem,v1,v2,v3)

@run mem L(ϕ)*f
