# The header part for testing boundaries in 2D
equations = HyperbolicDiffusionEquations2D()

@inline function initial_condition_harmonic_nonperiodic(x, t, equations::HyperbolicDiffusionEquations2D)
    if t == 0.0
        phi = 1.0
        q1 = 1.0
        q2 = 1.0
    else
        C = inv(sinh(pi))
        sinpi_x1, cospi_x1 = sincos(pi * x[1])
        sinpi_x2, cospi_x2 = sincos(pi * x[2])
        sinh_pix1 = sinh(pi * x[1])
        cosh_pix1 = cosh(pi * x[1])
        sinh_pix2 = sinh(pi * x[2])
        cosh_pix2 = cosh(pi * x[2])
        phi = C * (sinh_pix1 * sinpi_x2 + sinh_pix2 * sinpi_x1)
        q1 = C * pi * (cosh_pix1 * sinpi_x2 + sinh_pix2 * cospi_x1)
        q2 = C * pi * (sinh_pix1 * cospi_x2 + cosh_pix2 * sinpi_x1)
    end
    return SVector(phi, q1, q2)
end

initial_condition = initial_condition_harmonic_nonperiodic

boundary_conditions = BoundaryConditionDirichlet(initial_condition)

solver = DGSEM(polydeg=4, surface_flux=flux_godunov)

coordinates_min = (0.0, 0.0)
coordinates_max = (1.0, 1.0)
mesh = TreeMesh(coordinates_min, coordinates_max,
    initial_refinement_level=3,
    n_cells_max=30_000,
    periodicity=false)

semi = SemidiscretizationHyperbolic(mesh, equations, initial_condition, solver,
    boundary_conditions=boundary_conditions,
    source_terms=source_terms_harmonic)

@unpack mesh, equations, initial_condition, boundary_conditions, source_terms, solver, cache = semi

t = 0.0
l = nvariables(equations) * nnodes(solver)^ndims(mesh) * nelements(solver, cache)
du_ode = rand(Float64, l)
u_ode = rand(Float64, l)
du = wrap_array(du_ode, mesh, equations, solver, cache)
u = wrap_array(u_ode, mesh, equations, solver, cache)