density(q::Quadrature, fs::VT) where { N <: Int, VT <: AbstractArray{Float64, N} } = sum(fs, dims = N)
density(q::Quadrature, f::VT) where { VT <: AbstractVector{Float64}} = sum(f)

function velocity!(q::Quadrature, f::P, ρ::Float64, u::VT) where {VT <: AbstractVector{Float64}, P <: Population }
    @inbounds for d = 1:dimension(q)
        u[d] = 0.0
        for idx = 1:length(q.weights)
            u[d] += f[idx] * q.abscissae[d, idx]
        end
        u[d] /= ρ
    end
    return
end

function pressure(
    q::Quadrature,
    f::VT,
    ρ::Float64,
    u::VT,
)::Float64 where { VT <: AbstractVector{Float64}}
    a_2 = sum(f[idx] * hermite(Val{2}, q.abscissae[:, idx], q) for idx = 1:length(q.weights))
    D = dimension(q)

    p = (tr(a_2) - ρ * (u[1]^2 + u[2]^2 - D)) / D
    return p
end

function momentum_flux(q::Quadrature, f::VT, ρ::Float64, u::VT) where { VT <: AbstractVector{Float64}}
    D = dimension(q)
    P = zeros(D, D)
    @inbounds for x_idx = 1:D, y_idx = 1:D
        P[x_idx, y_idx] = sum(
            # Pressure tensor
            f[f_idx] *
            (q.abscissae[x_idx, f_idx] - u[x_idx]) *
            (q.abscissae[y_idx, f_idx] - u[y_idx])

            # Stress tensor
            # f[f_idx] * (q.abscissae[x_idx, f_idx]) * (q.abscissae[y_idx, f_idx])
            for f_idx = 1:length(f)
        ) #- ρ * u[x_idx] * u[y_idx]
    end

    return q.speed_of_sound_squared * P #- I * pressure(q, f, ρ, u)

    E = 0.0
    @inbounds for idx = 1:length(f)
        E += f[idx] * (q.abscissae[1, idx]^2 + q.abscissae[2, idx]^2)
    end

    p = q.speed_of_sound_squared * (E - ρ * (u[1]^2 + u[2]^2)) / D
    return p
end

function temperature(q::Quadrature, f::VT, ρ::Float64, u::VT) where { VT <: AbstractVector{Float64} }
    return pressure(q, f, ρ, u) ./ ρ
end

"""
Computes the deviatoric tensor σ

τ is the relaxation time such that ν = cs^2 τ
"""
function deviatoric_tensor(q::Quadrature, τ, f::VT, ρ::Float64, u::VT) where { VT <: AbstractVector{Float64} }
    D = dimension(q)

    a_bar_2 = sum([f[idx] * hermite(Val{2}, q.abscissae[:, idx], q) for idx = 1:length(q.weights)])
    a_eq_2 = equilibrium_coefficient(Val{2}, q, ρ, u, 1.0)
    σ = (a_bar_2 - a_eq_2) / (1 + 1 / (2 * τ))
    return σ - I * tr(σ) / D
end
