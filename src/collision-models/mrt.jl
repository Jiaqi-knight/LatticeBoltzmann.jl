struct MRT{Force} <: CollisionModel
    τs::Vector{Float64}

    # We will be using Hermite polynomials to compute the corresponding coefficients
    H0::Float64
    Hs::Array{Array{T, 1} where T}
    # Keep higher order coefficients allocated
    As::Array{Array{T, 1} where T}

    force::Force
end

function MRT(q::Quadrature, τs::Vector{Float64}, force = nothing)
    N = round(Int, order(q) / 2)
    Hs = [
        [
            hermite(Val{n}, q.abscissae[:, i], q)
            for i = 1:length(q.weights)
        ]
        for n = 1:N
    ]

    MRT(
        τs,
        1.0,
        Hs,
        copy(Hs),
        force
    )
end

function CollisionModel(
    cm::Type{<:MRT},
    q::Quadrature,
    problem::FluidFlowProblem
)
    τ = q.speed_of_sound_squared * lattice_viscosity(problem) + 0.5
    τs = fill(τ, order(q))

    if has_external_force(problem)
        force_field = (x_idx, y_idx, t) -> lattice_force(problem, x_idx, y_idx, t)

        return MRT(q, τs, force_field)
    end

    return MRT(q, τs)
end

function collide!(collision_model::MRT, q, f_in, f_out; time = 0.0, problem = nothing)
    collide_mrt!(collision_model, q, f_in, f_out, time = time, problem = problem)
end

# NOTE: we can do some clever optimizations where we check the value of τ_n
# If it is equal to 1, then we don't need to compute the nth hermite coefficient
# of f
function collide_mrt!(
    collision_model::CM,
    q,
    f_in,
    f_out;
    time = 0.0,
    problem = nothing
) where { CM <: CollisionModel }
    @info "Using a special collision operator"
    cs = q.speed_of_sound_squared
    τ_2 = cs * problem.ν + 0.5
    # τ_3 = cs * problem.κ + 0.5
    τ_3 = τ_2

    # TRT
    τs = [1.0, τ_2, τ_3, τ_2, τ_3]
    # τs = [1.0, 1.0, 1.5, 1.0, 1.5]

    D = dimension(q)
    N = div(lbm.order(q), 2)

    # Compute (get!?) the hermite polynomials for this quadrature
    Hs = [
        [
            hermite(Val{n}, q.abscissae[:, i], q)
            for i = 1:length(q.weights)
        ]
        for n = 1:N
    ]

    nx, ny, nf = size(f_in)

    f = Array{Float64}(undef, nf)
    u = zeros(dimension(q))
    @inbounds for x_idx = 1 : nx, y_idx = 1 : ny
        @inbounds for f_idx = 1 : nf
            f[f_idx] = f_in[x_idx, y_idx, f_idx]
        end

        # NOTE: we could optimize this by only computing upto n = 2 when τ = 1.0
        a_f = [
            sum([f[idx] * Hs[n][idx] for idx = 1:length(q.weights)])
            for n = 1:N
        ]

        ρ = density(q, f)
        velocity!(q, f, ρ, u)
        # T = temperature(q, f, ρ, a_f[1], a_f[2])
        T = 1.0

        # NOTE: we don't need to compute the 0th and 1st coefficient as these are equal
        # to a_f[0] and a_f[1]
        a_eq = [
            equilibrium_coefficient(Val{n}, q, ρ, u, T)
            for n = 1:N
        ]

        a_coll = [
            (1 - 1 / τs[n]) .* a_f[n] .+ (1 / τs[n]) .* a_eq[n]
            for n = 1:N
        ]

        @inbounds for f_idx = 1 : nf
            f_out[x_idx, y_idx, f_idx] = q.weights[f_idx] * (
                ρ +
                cs * ρ * sum(u .* Hs[1][f_idx]) +
                sum([
                    cs^n * dot(a_coll[n], Hs[n][f_idx]) / (factorial(n))
                    for n = 2:N
                ])
            )
        end
    end
    return
end