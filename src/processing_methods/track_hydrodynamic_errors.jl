import LinearAlgebra: norm

struct TrackHydrodynamicErrors{T} <: ProcessingMethod
    problem::FluidFlowProblem
    should_process::Bool
    n_steps::Int64
    stop_criteria::StopCriteria
    df::T
end
TrackHydrodynamicErrors(
    problem,
    should_process,
    n_steps,
    stop_criteria = StopCriteria(problem),
) = TrackHydrodynamicErrors(
    problem,
    should_process,
    n_steps,
    stop_criteria,
    Vector{
        NamedTuple{
            (
                :timestep,
                :error_ρ,
                :error_u,
                :error_p,
                :error_σ_xx,
                :error_σ_xy,
                :error_σ_yy,
                :error_σ_yx,
                :mass,
                :momentum,
                :energy,
            ),
            Tuple{
                Int64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
                Float64,
            },
        },
    }(),
)

function next!(process_method::TrackHydrodynamicErrors, q, f_in, t::Int64)
    should_stop = false

    if mod(t, 100) == 0
        if (should_stop!(process_method.stop_criteria, q, f_in))
            @info "Stopping after $t iterations"
            should_stop = true
        end
    end

    if (should_stop == false && t != process_method.n_steps)
        if (!process_method.should_process)
            return false
        end
    end

    problem = process_method.problem
    nx, ny, nf = size(f_in)
    x_range, y_range = range(problem)

    f = Array{Float64}(undef, size(f_in, 3))
    u = zeros(dimension(q))
    expected_u = zeros(dimension(q))

    error_ρ = 0.0
    error_u = 0.0
    error_p = 0.0
    error_σ_xx = 0.0
    error_σ_xy = 0.0
    error_σ_yy = 0.0
    error_σ_yx = 0.0

    time = t * delta_t(problem)
    Δ = Float64(y_range.step) * Float64(x_range.step)
    if (nx == 1)
        Δ = Float64(y_range.step)
        if (ny == 1)
            Δ = 1.0
        end
    elseif ny == 1
        Δ = Float64(x_range.step)
    end
    Δ_ = Δ
    Δ = 1.0

    τ = q.speed_of_sound_squared * LatticeBoltzmann.lattice_viscosity(problem) + 0.5

    D = dimension(q)
    N = div(LatticeBoltzmann.order(q), 2)
    N = 2
    Hs = [[hermite(Val{n}, q.abscissae[:, i], q) for i in 1:length(q.weights)] for n in 1:N]

    total_expected_u_squared = 0.0
    total_expected_σ_xx_squared = 0.0
    total_expected_σ_yy_squared = 0.0
    total_expected_σ_xy_squared = 0.0
    total_expected_σ_yx_squared = 0.0
    total_expected_p_squared = 0.0

    total_mass = 0.0
    total_momentum = 0.0
    total_energy = 0.0
    @inbounds for x_idx in 1:nx, y_idx in 1:ny
        # Analytical
        x = x_range[x_idx]
        y = y_range[y_idx]

        # Compute expected marcroscopic variables
        expected_ρ = LatticeBoltzmann.density(q, problem, x, y, time)
        expected_u = LatticeBoltzmann.velocity(problem, x, y, time)
        expected_p = LatticeBoltzmann.pressure(q, problem, x, y, time)
        expected_ϵ = (dimension(q) / 2) * expected_p / expected_ρ
        expected_T = expected_p / expected_ρ
        expected_σ = deviatoric_tensor(q, problem, x, y, time)

        total_expected_u_squared += sum(expected_u .^ 2)# norm(expected_u, 2)^2
        total_expected_σ_xx_squared += expected_σ[1, 1]^2
        total_expected_σ_yy_squared += expected_σ[2, 2]^2
        total_expected_σ_xy_squared += expected_σ[1, 2]^2
        total_expected_σ_yx_squared += expected_σ[2, 1]^2
        total_expected_p_squared += expected_p^2

        # Compute macroscopic variables
        @inbounds for f_idx in 1:size(f_in, 3)
            f[f_idx] = f_in[x_idx, y_idx, f_idx]
        end

        ρ = density(q, f)
        velocity!(q, f, ρ, u)
        p = pressure(q, f, ρ, u)

        # Adding the forcing term moves the optimal tau for poiseuille flows
        # F = cm.force(x_idx, y_idx, 0.0)
        # u += cm.τ * F

        # Hermite coefficients of \bar{f}
        τ = q.speed_of_sound_squared * LatticeBoltzmann.lattice_viscosity(problem)
        a_bar_2 = sum([f[idx] * Hs[2][idx] for idx in 1:length(q.weights)])
        a_eq_2 = equilibrium_coefficient(Val{2}, q, ρ, u, 1.0)

        # Determin a^2 of f based on \bar{f} and f^eq
        a_2 = (a_bar_2 + (1 / (2 * τ)) * a_eq_2) / (1 + 1 / (2 * τ))

        # Second order convergence?
        # P = (1 - 1 / (2 * τ))a_f[2] - (a_f[1] * a_f[1]') / ρ + ρ * I
        p = 0.0
        cs = 1 / q.speed_of_sound_squared
        for x_idx in 1:D
            # NOTE the (1 - 1/2τ) term probably comes from
            # σ = - (1 - 1/2τ) ∑ f^(1)_i c_i c_i
            # p += (1 - 1 / (2 * τ)) * a_bar_2[x_idx, x_idx] - ρ * (u[x_idx] * u[x_idx] - I)

            # Should be identical / better ?
            p += a_bar_2[x_idx, x_idx] - ρ * (u[x_idx] * u[x_idx] - I)
            # p += a_bar_2[x_idx, x_idx] - ρ * u[x_idx] * u[x_idx] + D * ρ * (1 + (1 - cs) / (2 * τ))
        end
        p /= D
        p1 = p
        # p = tr(a_bar_2 - ρ * (u * u' - I) ) / D

        # Huidige poging
        P = a_2 - ρ * (u * u' - I)
        σ_lb = P - I * tr(P) / D

        τ = q.speed_of_sound_squared * LatticeBoltzmann.lattice_viscosity(problem)
        σ_lb = deviatoric_tensor(q, τ, f, ρ, u)
        # σ_lb = deviatoric_tensor(q, problem.τ * q.speed_of_sound_squared, f, ρ, u)

        # Gives 4th order convergence?
        p = tr(P) / D

        # Determine errors by first scaling from lattice variables to dimensionless
        ρ = dimensionless_density(problem, ρ)
        u = dimensionless_velocity(problem, u)
        p = dimensionless_pressure(q, problem, p)
        σ_lb = dimensionless_stress(problem, σ_lb)

        # - \mu \rho T \Lambda
        σ_err = (expected_σ .- σ_lb)

        error_p += Δ * (p - expected_p)^2
        error_ρ += Δ * (ρ - expected_ρ)^2
        error_u += Δ * ((u[1] - expected_u[1])^2 + (u[2] - expected_u[2])^2)
        error_σ_xx += Δ * (expected_σ[1, 1] .- σ_lb[1, 1])^2
        error_σ_xy += Δ * (expected_σ[1, 2] .- σ_lb[1, 2])^2
        error_σ_yx += Δ * (expected_σ[2, 1] .- σ_lb[2, 1])^2
        error_σ_yy += Δ * (expected_σ[2, 2] .- σ_lb[2, 2])^2

        total_mass += ρ
        total_momentum += ρ * sum(u)
        total_energy += ρ * sum(u .^ 2)
    end

    push!(
        process_method.df,
        (
            timestep = t,
            error_ρ = sqrt(error_ρ),
            error_u = sqrt(error_u / total_expected_u_squared),
            # error_u = sqrt(error_u),# / total_expected_u_squared),
            error_p = sqrt(error_p / total_expected_p_squared),
            error_σ_xx = sqrt(error_σ_xx / total_expected_σ_xx_squared),
            error_σ_xy = sqrt(error_σ_xy / total_expected_σ_xy_squared),
            error_σ_yy = sqrt(error_σ_yy / total_expected_σ_yy_squared),
            error_σ_yx = sqrt(error_σ_yx / total_expected_σ_yx_squared),
            mass = Δ_ * total_mass,
            momentum = Δ_ * total_momentum,
            energy = Δ_ * total_energy,
        ),
    )

    if mod(t, 1) == 0
        should_visualize = false
        if (process_method.should_process)
            if t == process_method.n_steps
                should_visualize = true
            end

            if mod(t, max(10, round(Int, process_method.n_steps / 25))) == 0
                should_visualize = true
            end
        end

        if (should_visualize)
            Δt = delta_t(process_method.problem)
            visualize(process_method.problem, q, f_in, time, process_method.df)
        end
    end

    return should_stop
end
