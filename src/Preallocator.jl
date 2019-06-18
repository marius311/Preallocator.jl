module Preallocator

using Cassette
using Printf

export @preallocate, @preallocated

"""
    mem = @preallocate <expression> [debug=true/false]
    
Runs `<expression>` and traces any Arrays which are allocated while running this
code. Returns a memory cache `mem`, which can then be used in a subsequent call
to `@preallocated mem <expression>` which reuses the same memory for these
Arrays rather than reallocating it.

`debug=true` prints some useful debugging info.
"""
macro preallocate(ex, debug=false)
    if debug != false
        if !(Meta.isexpr(debug, :(=)) && debug.args[1]==:debug && (debug=debug.args[2]) isa Bool)
            return error("Usage: @preallocate <ex> [debug=true/false]")
        end
    end
    quote
        ctx = PreallocateCtx(metadata=PreallocatorMemory(debug=$debug))
        Cassette.overdub(ctx, ()->$(esc(ex)))
        allocate(ctx.metadata)
    end
end

"""
    @preallocated mem <expression>
    
Uses the preallocated memory cache `mem` to run `<expression>`. See
`@preallocate`.
"""
macro preallocated(mem, ex)
    quote
        mem = rewind($(esc(mem)))
        ans = Cassette.overdub(PreallocatedCtx(metadata=mem), ()->$(esc(ex)))
        if mem.debug
            @info @sprintf("""
            @preallocate
            Total arrays used: %i of %i (%.1f%%)
            Total cache misses: %i (%.1f%%)
            """, 
            (used=max(length(mem.allocated_arrays),mem.next_index-1)), 
            (total=length(mem.allocated_arrays)),
            100 * used/total,
            mem.cache_misses,
            100 * mem.cache_misses / (total+mem.cache_misses))
        end
        return ans
    end
end


Base.@kwdef mutable struct PreallocatorMemory
    allocated_arrays :: Vector{Any} = []
    next_index :: Int = 1
    debug :: Bool = false
    cache_misses :: Int = 0
end
rewind(mem::PreallocatorMemory) = PreallocatorMemory(allocated_arrays=mem.allocated_arrays, debug=mem.debug)


function allocate(mem)
    allocated_arrays = []
    
    for (i,A,args) in mem.allocated_arrays
        if i isa Int
            push!(allocated_arrays, allocated_arrays[i])
        else
            push!(allocated_arrays, A(undef,args...))
        end
    end
    
    if mem.debug
        @info @sprintf("""
        @preallocate
        Total array allocations: %i (%i unique arrays needed)
        Total memory allocated: %.2fMb
        """, 
        length(allocated_arrays), 
        length([1 for (i,) in mem.allocated_arrays if !(i isa Int)]),
        Base.summarysize(allocated_arrays)/1024^2)
    end
    
    return PreallocatorMemory(allocated_arrays=allocated_arrays, debug=mem.debug)
end


function find_reusable_memory(allocated_arrays, A, args)
    findfirst(((wref, A′, args′),)->(wref==nothing && A==A′ && args==args′), allocated_arrays)
end

# on the @preallocate pass, save the memory after its allocated
Cassette.@context PreallocateCtx
function Cassette.posthook(ctx::PreallocateCtx, output, ::Type{A}, ::UndefInitializer, args::Int...) where {T,N,A<:Array{T,N}}
    mem = ctx.metadata
    GC.gc(false)
    if (i = find_reusable_memory(mem.allocated_arrays, A, args)) != nothing
        mem.allocated_arrays[i] = (WeakRef(output), A, args)
        push!(mem.allocated_arrays, (i, A, args))
    else
        push!(mem.allocated_arrays, (WeakRef(output), A, args))
    end
end

# on the @preallocated pass, replace allocations with using the preallocated memory instead
Cassette.@context PreallocatedCtx
function Cassette.overdub(ctx::PreallocatedCtx, ::Type{A}, ::UndefInitializer, args::Int...) where {T,N,A<:Array{T,N}}
    mem = ctx.metadata
    if (mem.next_index <= length(mem.allocated_arrays)) && ((arr = mem.allocated_arrays[mem.next_index]) isa A)
        mem.next_index += 1
        return arr :: A
    else
        mem.cache_misses += 1
        return A(undef, args...)
    end
end

end
