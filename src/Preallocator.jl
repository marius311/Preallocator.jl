module Preallocator

using Cassette

export @preallocate, @preallocated

"""
    mem = @preallocate <expression>
    
Runs `<expression>` and monitors any Arrays which are allocated while running
this code. Returns a list `mem` of these arrays, which can then be used in a
subsequent call to `@preallocated mem <expression>` which makes it so that the same
memory is used again rather than being reallocated.
"""
macro preallocate(ex)
    quote
        ctx = PreallocateCtx(metadata=[])
        Cassette.overdub(ctx, ()->$(esc(ex)))
        reverse(ctx.metadata)
    end
end

"""
    @preallocated mem <expression>
    
Uses the preallocated memory `mem` to run `<expression>`. See `@preallocate`.
"""
macro preallocated(mem, ex)
    quote
        Cassette.overdub(PreallocatedCtx(metadata=copy($(esc(mem)))), ()->$(esc(ex)))
    end
end


# on the @preallocate pass, save the memory after its allocated
Cassette.@context PreallocateCtx
function Cassette.posthook(ctx::PreallocateCtx, output, ::Type{A}, ::UndefInitializer, args::Int...) where {T,N,A<:Array{T,N}}
    push!(ctx.metadata, output)
end

# on the @preallocated pass, replace allocations with using the preallocated memory instead
Cassette.@context PreallocatedCtx
function Cassette.overdub(ctx::PreallocatedCtx, ::Type{A}, ::UndefInitializer, args::Int...) where {T,N,A<:Array{T,N}}
    pop!(ctx.metadata) :: A
end

end
