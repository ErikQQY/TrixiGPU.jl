module TrixiGPU

# Include other packages that are used in TrixiGPU.jl (# FIXME: Remember to reorder)
# using Reexport: @reexport

using CUDA: @cuda, CuArray, HostKernel,
            threadIdx, blockIdx, blockDim, similar,
            launch_configuration

using Trixi: AbstractEquations, TreeMesh, DGSEM,
             BoundaryConditionPeriodic, SemidiscretizationHyperbolic,
             VolumeIntegralWeakForm,
             flux, ntuple, nvariables,
             True, False,
             wrap_array, compute_coefficients, have_nonconservative_terms

import Trixi: get_node_vars, get_node_coords, get_surface_node_vars

using SciMLBase: ODEProblem, FullSpecialize

using StrideArrays: PtrArray

using StaticArrays: SVector

using SimpleUnPack: @unpack

# Include other source files
include("function.jl")
include("auxiliary/auxiliary.jl")
include("solvers/solvers.jl")

# Export the public APIs
# export configurator_1d, configurator_2d, configurator_3d

end
