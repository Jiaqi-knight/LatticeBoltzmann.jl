struct LatticeBoltzmannModel{
    Q <: Quadrature,
    T,
    CM <: CollisionModel,
    PM <: ProcessingMethod,
    BCs <: AbstractVector{<:BoundaryCondition},
}
    f_stream::T
    f_collision::T
    quadrature::Q
    collision_model::CM
    boundary_conditions::BCs
    processing_method::PM
end
function LatticeBoltzmannModel(
    problem,
    quadrature;
    collision_model = SRT,
    initialization_strategy = InitializationStrategy(problem),
    process_method,
)
    f_stream = initialize(initialization_strategy, quadrature, problem, collision_model)
    f_collision = copy(f_stream)

    LatticeBoltzmannModel(
        f_stream,
        f_collision,
        quadrature,
        CollisionModel(collision_model, quadrature, problem),
        boundary_conditions(problem),
        process_method,
    )
end
function simulate(
    problem::FluidFlowProblem,
    q::Quadrature;
    process_method = nothing,
    should_process = true,
    initialization_strategy = InitializationStrategy(problem),
    t_end = 1.0,
    collision_model = SRT,
)
    Δt = delta_t(problem)
    n_steps = round(Int, t_end / Δt)

    if isnothing(process_method)
        process_method = ProcessingMethod(problem, should_process, n_steps)
    end

    model = LatticeBoltzmannModel(
        problem,
        q,
        collision_model = collision_model,
        initialization_strategy = initialization_strategy,
        process_method = process_method,
    )

    simulate(model, 0:n_steps)
end
function simulate(model::LatticeBoltzmannModel, time)
    Δt = isdefined(model.processing_method, :problem) ?
        delta_t(model.processing_method.problem) : 0.0

    @inbounds for t in time
        collide!(model, time = t * Δt)
        stream!(model)
        apply_boundary_conditions!(model, time = t * Δt)

        if next!(model, t + 1)
            return model
        end
    end

    next!(model, last(time) + 1)

    model
end

# The following are helper functions which use the old interface where we
# explicitely pass the quadrature, collision model etc.
# This will likely be refactored so that we can write specialized function
# for each specific LatticeBoltzmannModel (once we also introduce ddf models)

function collide!(model::LatticeBoltzmannModel; time)
    collide!(
        model.collision_model,
        model.quadrature,
        f_new = model.f_collision,
        f_old = model.f_stream,
        time = time,
    )
end

function stream!(model::LatticeBoltzmannModel)
    stream!(model.quadrature, f_new = model.f_stream, f_old = model.f_collision)
end

function apply_boundary_conditions!(model::LatticeBoltzmannModel; time = 0.0)
    apply!(
        model.boundary_conditions,
        model.quadrature,
        model.f_stream,
        model.f_collision,
        time = time,
    )
end

function next!(model::LatticeBoltzmannModel, t::Int64)
    next!(model.processing_method, model.quadrature, model.f_stream, t)
end
