export TaylorGreenVortexDecay,
    TaylorGreenVortexExample,
    density,
    velocity,
    pressure,
    temperature,
    decay,
    force,
    initialize

struct TaylorGreenVortexExample <: lbm.InitialValueProblem
    scale::Int
    rho_0::Float64
    u_max::Float64
    ν::Float64
    NX::Int64
    NY::Int64
    k_x::Float64
    k_y::Float64
    domain_size::Tuple{Float64, Float64}

    function TaylorGreenVortexExample(ν = 1.0 / 6.0 , scale = 2, NX = 16 * scale, NY = NX, domain_size = (2pi, 2pi))
        u_max = 0.02 / scale
        Re = NX * u_max / ν
        @show Re
        return new(
            scale,
            1.0,
            u_max,
            ν,
            NX,
            NY,
            domain_size[1] / NX,
            domain_size[2] / NY,
            domain_size
        )
    end
end

function viscosity(problem::TaylorGreenVortexExample)
    return problem.ν
end

function density(q::Quadrature, tgv::TaylorGreenVortexExample, x::Float64, y::Float64, timestep::Float64 = 0.0)
    # return pressure(q, tgv, x, y, timestep)
    
    # If not athermal
    return 1.0
end

function pressure(q::Quadrature, tgv::TaylorGreenVortexExample, x::Float64, y::Float64, timestep::Float64 = 0.0)
    P = -0.25 * tgv.rho_0 * tgv.u_max^2 * (
        (tgv.k_y / tgv.k_x) * cos(2.0 * x) +
        (tgv.k_x / tgv.k_y) * cos(2.0 * y)
    ) * decay(tgv, x, y, timestep)^2;

    return 1.0 + q.speed_of_sound_squared * P
end

function velocity(tgv::TaylorGreenVortexExample, x::Float64, y::Float64, timestep::Float64 = 0.0)
    u_max = tgv.u_max

    return decay(tgv, x, y, timestep) * [
      -u_max * sqrt(tgv.k_y / tgv.k_x) * cos(x) * sin(y),
       u_max * sqrt(tgv.k_x / tgv.k_y) * sin(x) * cos(y)
    ]
end
function decay(tgv::TaylorGreenVortexExample, x::Float64, y::Float64, timestep::Float64)
    return exp(-1.0 * timestep)
end

function force(tgv::TaylorGreenVortexExample, x::Float64, y::Float64, time::Float64 = 0.0)
    return (1 / tgv.ν) * (tgv.k_x^2 + tgv.k_y^2) * velocity(tgv, x, y, time)
end

function delta_t(problem::TaylorGreenVortexExample)
    ν = viscosity(problem)
    Δt = ν * (problem.k_x^2 + problem.k_y^2)

    return Δt
end
