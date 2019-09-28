module lbm
using BenchmarkTools
using TimerOutputs

include("quadratures/quadrature.jl")
include("stream.jl")
include("collision.jl")
# include("process.jl")
include("problems/problems.jl")

export Quadrature, Lattice, D2Q4, D2Q5, D2Q9, D2Q17
    initialize,
    density,
    momentum,
    pressure,
    total_energy,
    kinetic_energy,
    internal_energy,
    temperature,
    dimension,
    equilibrium,
    equilibrium!,
    hermite_equilibrium,
    hermite_first_nonequilibrium
export hermite

export stream
export CollisionModel,
    SRT,
    SRT_Force,
    TRT,
    collide,
    collide_2,
    collide_3

export simulate

using DataFrames
function process_stats()
    return DataFrame(
        [
            Float64[], Float64[], Float64[], Float64[], Float64[],
            Float64[], Float64[], Float64[], Float64[], Float64[],
            # Float64[],
            # Float64[],
            # Float64[],
            Float64[]
        ],
        [
            :density, :momentum, :total_energy, :kinetic_energy, :internal_energy,
            :density_a, :momentum_a, :total_energy_a, :kinetic_energy_a, :internal_energy_a,
            # :density_e,
            # :momentum_e,
            # :kinetic_energy_e,
            :u_error
        ]
    )
end

function siumlate(problem::InitialValueProblem, quadrature::Quadrature = D2Q9();
                  n_steps = 200 * problem.scale * problem.scale)
    # initialize
    f_out, collision_operator = lbm.initialize(quadrature, problem)
    f_in = copy(f_out)
    ν = viscosity(problem)
    Δt = lbm.delta_t(problem)
    @show Δt
    @show problem

    stats = process_stats()
    # lbm.process!(problem, quadrature, f_in, 0.0 * Δt, stats, should_visualize = true)
    @inbounds for t = 0:n_steps
        if mod(t, round(Int, n_steps / 10)) == 0
            @show t, t / n_steps
        end

        if (mod(t, 1) == 0)
            lbm.process!(
                problem,
                quadrature,
                f_in,
                t * 1.0, #* Δt,
                stats,
                should_visualize = (mod(t, round(Int, n_steps / 10)) == 0)
                # should_visualize = true
            )
        end

        collide!(collision_operator, quadrature, f_in, f_out, time = t * Δt)
        # for f_idx = 1:size(f_in, 3)
        #      # circshift!(f_in[:,:,f_idx], f_out[:,:,f_idx], quadrature.abscissae[:, f_idx]);

        #     f_in[:,:,f_idx] = circshift(f_out[:,:,f_idx], quadrature.abscissae[:, f_idx]);
        # end
        stream!(quadrature, f_out, f_in)
        # f_in = stream(quadrature, f_out)
        # apply boundary conditions

        # check_stability(f_in) || return :unstable, f_in, stats       )
    end
    # lbm.process!(problem, quadrature, f_in, n_steps * Δt, stats, should_visualize = true)

    # @show stats

    f_in, stats
end

# export process!

# abstract type Model

# struct Problem{Model}
#     model::Model
#     # model::Model
#     # quadrature::Quadrature
#     # collision::Collision
#     N::Int64      # rename to points / cells / ...
#     N_iter::Int64 # rename to iterations?
# end

# # Put collision_model, relaxation_rate, simulate, initial_condition, here..

# # abstract Quadrature;
# # Distribution{D2Q9}
# # Distribution{D2Q17}
# # immutable Distribution{T, Quadrature}
# #     fs::Array{T, 1}
# # end
# # typealias Distribution{T} Distribution{Float64, Q}

# typealias Distributions Array{Float64, 3}
# typealias Distribution Array{Float64, 2}

# include("quadratures/D2Q9.jl")
# # include("quadratures/D2Q4.jl")

# density(f::Distribution) = sum(f)

# velocity(f::Distribution) = velocity(f, abscissae, original_order)
# function velocity{D}(f::Distribution, abscissae::Array{Int64, D}, order::Array{Int64, 1})
#     ρ, u = density_and_velocity(f, abscissae, order)
#     return u
# end

# density_and_velocity(f::Distribution) = density_and_velocity(f, abscissae, original_order)
# function density_and_velocity{D}(f::Distribution, abscissae::Array{Int64, D}, order::Array{Int64, 1})::Tuple{Float64, Array{Float64, 1}}
#     u = zeros(D)
#     ρ = 0.0

#     # Compute: ∑fᵢ and ∑fᵢξᵢ
#     for idx ∈ order
#         for d = 1:D
#             u[d] += abscissae[d, idx] * f[idx]
#         end
#         ρ += f[idx]
#     end

#     return ρ, u / ρ
# end

# equilibrium(f::Distribution) = equilibrium(density_and_velocity(f, abscissae, original_order)...)
# equilibrium{T}(ρ::T, u::Array{T, 1})::Distribution = equilibrium(ρ, u, dot(u, u))
# equilibrium{T}(ρ::T, u::Array{T, 1}, u_squared::T)::Distribution = [equilibrium(ρ, u, u_squared, idx) for idx = 1:9]'
# function equilibrium{T}(rho::T, u::Array{T, 1}, u_squared::T, idx::Int)::T
#     const cs = dot(abscissae[:, idx], u)

#     return rho * weights[idx] .* (1.0 + 3.0 * cs + 4.5 * (cs .* cs) - 1.5 * u_squared)
# end

# """
# By default we will be using a bgk collision
# """
# collide(f::Distribution, ω)::Distribution = bgk_collision(f, ω)
# collide(f::Distribution, ω, force)::Distribution = bgk_collision(f, ω, force)

# """
# Apply the most simple collision operator
# """
# function bgk_collision{T}(f::Distribution, ω::T)::Distribution
#     const ρ, u = density_and_velocity(f)

#     bgk_collision(f, ω, ρ, u)
# end

# """
# Apply the bgk collision operator after adding additional momentum
# to the velocity due to a force term
# """
# function bgk_collision{T}(f::Distribution, ω::T, force::Array{T, 1})::Distribution
#     const ρ, u = density_and_velocity(f)

#     bgk_collision(f, ω, ρ, u + force / ω)
# end

# function bgk_collision{T}(f::Distribution, ω::T, ρ::T, u::Array{T, 1})
#     const u_squared = dot(u, u)

#     for idx = 1:9
#         f[idx] = (1 - ω) * f[ if next_x > lx
#         next_x -= lx
#     elseif next_x < 1
#         next_x += lx
#     end

#     next_y = y - abscissae[2, f_idx]
#     if next_y > ly
#         next_y -= ly
#     elseif next_y < 1
#         next_y += ly
#     end

#     return next_x, next_y
# end


end
