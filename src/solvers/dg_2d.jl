# Everything related to a DG semidiscretization in 2D

# Functions that end with `_kernel` are CUDA kernels that are going to be launched by 
# the @cuda macro with parameters from the kernel configurator. They are purely run on 
# the device (i.e., GPU).

# Kernel for calculating fluxes along normal direction
function flux_kernel!(flux_arr1, flux_arr2, u, equations::AbstractEquations{2},
                      flux::Function)
    j = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    k = (blockIdx().y - 1) * blockDim().y + threadIdx().y

    if (j <= size(u, 2)^2 && k <= size(u, 4))
        j1 = div(j - 1, size(u, 2)) + 1
        j2 = rem(j - 1, size(u, 2)) + 1

        u_node = get_node_vars(u, equations, j1, j2, k)

        flux_node1 = flux(u_node, 1, equations)
        flux_node2 = flux(u_node, 2, equations)

        @inbounds begin
            for ii in axes(u, 1)
                flux_arr1[ii, j1, j2, k] = flux_node1[ii]
                flux_arr2[ii, j1, j2, k] = flux_node2[ii]
            end
        end
    end

    return nothing
end

# Kernel for calculating weak form
function weak_form_kernel!(du, derivative_dhat, flux_arr1, flux_arr2)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    k = (blockIdx().z - 1) * blockDim().z + threadIdx().z

    if (i <= size(du, 1) && j <= size(du, 2)^2 && k <= size(du, 4))
        j1 = div(j - 1, size(du, 2)) + 1
        j2 = rem(j - 1, size(du, 2)) + 1

        @inbounds begin
            for ii in axes(du, 2)
                du[i, j1, j2, k] += derivative_dhat[j1, ii] * flux_arr1[i, ii, j2, k]
                du[i, j1, j2, k] += derivative_dhat[j2, ii] * flux_arr2[i, j1, ii, k]
            end
        end
    end

    return nothing
end

# Kernel for prolonging two interfaces 
function prolong_interfaces_kernel!(interfaces_u, u, neighbor_ids, orientations)
    j = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    k = (blockIdx().y - 1) * blockDim().y + threadIdx().y

    if (j <= size(interfaces_u, 2) * size(interfaces_u, 3) && k <= size(interfaces_u, 4))
        j1 = div(j - 1, size(interfaces_u, 3)) + 1
        j2 = rem(j - 1, size(interfaces_u, 3)) + 1

        orientation = orientations[k]
        left_element = neighbor_ids[1, k]
        right_element = neighbor_ids[2, k]

        @inbounds begin
            interfaces_u[1, j1, j2, k] = u[j1,
                                           isequal(orientation, 1) * size(u, 2) + isequal(orientation, 2) * j2,
                                           isequal(orientation, 1) * j2 + isequal(orientation, 2) * size(u,
                                                                                                         2),
                                           left_element]
            interfaces_u[2, j1, j2, k] = u[j1,
                                           isequal(orientation, 1) * 1 + isequal(orientation, 2) * j2,
                                           isequal(orientation, 1) * j2 + isequal(orientation, 2) * 1,
                                           right_element]
        end
    end

    return nothing
end

# Kernel for calculating surface fluxes 
function surface_flux_kernel!(surface_flux_arr, interfaces_u, orientations,
                              equations::AbstractEquations{2}, surface_flux::Any)
    j2 = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    k = (blockIdx().y - 1) * blockDim().y + threadIdx().y

    if (j2 <= size(surface_flux_arr, 3) && k <= size(surface_flux_arr, 4))
        u_ll, u_rr = get_surface_node_vars(interfaces_u, equations, j2, k)
        orientation = orientations[k]

        surface_flux_node = surface_flux(u_ll, u_rr, orientation, equations)

        @inbounds begin
            for j1j1 in axes(surface_flux_arr, 2)
                surface_flux_arr[1, j1j1, j2, k] = surface_flux_node[j1j1]
            end
        end
    end

    return nothing
end

# Kernel for setting interface fluxes
function interface_flux_kernel!(surface_flux_values, surface_flux_arr, neighbor_ids,
                                orientations)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    k = (blockIdx().z - 1) * blockDim().z + threadIdx().z

    if (i <= size(surface_flux_values, 1) &&
        j <= size(surface_flux_arr, 3) &&
        k <= size(surface_flux_arr, 4))
        left_id = neighbor_ids[1, k]
        right_id = neighbor_ids[2, k]

        left_direction = 2 * orientations[k]
        right_direction = 2 * orientations[k] - 1

        @inbounds begin
            surface_flux_values[i, j, left_direction, left_id] = surface_flux_arr[1, i, j,
                                                                                  k]
            surface_flux_values[i, j, right_direction, right_id] = surface_flux_arr[1, i, j,
                                                                                    k]
        end
    end

    return nothing
end

# Kernel for calculating surface integrals
function surface_integral_kernel!(du, factor_arr, surface_flux_values,
                                  equations::AbstractEquations{2})
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    k = (blockIdx().z - 1) * blockDim().z + threadIdx().z

    if (i <= size(du, 1) && j <= size(du, 2)^2 && k <= size(du, 4))
        j1 = div(j - 1, size(du, 2)) + 1
        j2 = rem(j - 1, size(du, 2)) + 1

        @inbounds begin
            du[i, j1, j2, k] -= (surface_flux_values[i, j2, 1, k] * isequal(j1, 1) +
                                 surface_flux_values[i, j1, 3, k] * isequal(j2, 1)) *
                                factor_arr[1]
            du[i, j1, j2, k] += (surface_flux_values[i, j2, 2, k] *
                                 isequal(j1, size(du, 2)) +
                                 surface_flux_values[i, j1, 4, k] *
                                 isequal(j2, size(du, 2))) * factor_arr[2]
        end
    end

    return nothing
end

# CUDA kernel for applying inverse Jacobian 
function jacobian_kernel!(du, inverse_jacobian, equations::AbstractEquations{2})
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    k = (blockIdx().z - 1) * blockDim().z + threadIdx().z

    if (i <= size(du, 1) && j <= size(du, 2)^2 && k <= size(du, 4))
        j1 = div(j - 1, size(du, 2)) + 1
        j2 = rem(j - 1, size(du, 2)) + 1

        @inbounds du[i, j1, j2, k] *= -inverse_jacobian[k]
    end

    return nothing
end

# Functions that begin with `cuda_` are the functions that pack CUDA kernels together to do 
# partial work in semidiscretization. They are used to invoke kernels from the host (i.e., CPU) 
# and run them on the device (i.e., GPU).

# Pack kernels for calculating volume integrals
function cuda_volume_integral!(du, u, mesh::TreeMesh{2}, nonconservative_terms, equations,
                               volume_integral::VolumeIntegralWeakForm, dg::DGSEM)
    derivative_dhat = CuArray{Float32}(dg.basis.derivative_dhat)
    flux_arr1 = similar(u)
    flux_arr2 = similar(u)

    size_arr = CuArray{Float32}(undef, size(u, 2)^2, size(u, 4))

    flux_kernel = @cuda launch=false flux_kernel!(flux_arr1, flux_arr2, u, equations, flux)
    flux_kernel(flux_arr1, flux_arr2, u, equations;
                configurator_2d(flux_kernel, size_arr)...,)

    size_arr = CuArray{Float32}(undef, size(du, 1), size(du, 2)^2, size(du, 4))

    weak_form_kernel = @cuda launch=false weak_form_kernel!(du, derivative_dhat, flux_arr1,
                                                            flux_arr2)
    weak_form_kernel(du, derivative_dhat, flux_arr1, flux_arr2;
                     configurator_3d(weak_form_kernel, size_arr)...,)

    return nothing
end

# Pack kernels for prolonging solution to interfaces
function cuda_prolong2interfaces!(u, mesh::TreeMesh{2}, cache)
    neighbor_ids = CuArray{Int64}(cache.interfaces.neighbor_ids)
    orientations = CuArray{Int64}(cache.interfaces.orientations)
    interfaces_u = CuArray{Float32}(cache.interfaces.u)

    size_arr = CuArray{Float32}(undef,
                                size(interfaces_u, 2) * size(interfaces_u, 3),
                                size(interfaces_u, 4))

    prolong_interfaces_kernel = @cuda launch=false prolong_interfaces_kernel!(interfaces_u,
                                                                              u,
                                                                              neighbor_ids,
                                                                              orientations)
    prolong_interfaces_kernel(interfaces_u, u, neighbor_ids, orientations;
                              configurator_2d(prolong_interfaces_kernel, size_arr)...,)

    cache.interfaces.u = interfaces_u  # copy back to host automatically

    return nothing
end

# Pack kernels for calculating interface fluxes
function cuda_interface_flux!(mesh::TreeMesh{2}, nonconservative_terms::False, equations,
                              dg::DGSEM, cache)
    surface_flux = dg.surface_integral.surface_flux

    neighbor_ids = CuArray{Int64}(cache.interfaces.neighbor_ids)
    orientations = CuArray{Int64}(cache.interfaces.orientations)
    interfaces_u = CuArray{Float32}(cache.interfaces.u)
    surface_flux_arr = CuArray{Float32}(undef, 1, size(interfaces_u)[2:end]...)
    surface_flux_values = CuArray{Float32}(cache.elements.surface_flux_values)

    size_arr = CuArray{Float32}(undef, size(interfaces_u, 3), size(interfaces_u, 4))

    surface_flux_kernel = @cuda launch=false surface_flux_kernel!(surface_flux_arr,
                                                                  interfaces_u,
                                                                  orientations, equations,
                                                                  surface_flux)
    surface_flux_kernel(surface_flux_arr, interfaces_u, orientations, equations,
                        surface_flux; configurator_2d(surface_flux_kernel, size_arr)...,)

    size_arr = CuArray{Float32}(undef, size(surface_flux_values, 1), size(interfaces_u, 3),
                                size(interfaces_u, 4))

    interface_flux_kernel = @cuda launch=false interface_flux_kernel!(surface_flux_values,
                                                                      surface_flux_arr,
                                                                      neighbor_ids,
                                                                      orientations)
    interface_flux_kernel(surface_flux_values, surface_flux_arr, neighbor_ids, orientations;
                          configurator_3d(interface_flux_kernel, size_arr)...,)

    cache.elements.surface_flux_values = surface_flux_values # copy back to host automatically

    return nothing
end

# Dummy function for asserting boundaries
function cuda_prolong2boundaries!(u, mesh::TreeMesh{2},
                                  boundary_condition::BoundaryConditionPeriodic, cache)
    @assert iszero(length(cache.boundaries.orientations))
end

# Dummy function for asserting boundary fluxes
function cuda_boundary_flux!(t, mesh::TreeMesh{2},
                             boundary_condition::BoundaryConditionPeriodic, equations,
                             dg::DGSEM, cache)
    @assert iszero(length(cache.boundaries.orientations))
end

# Pack kernels for calculating surface integrals
function cuda_surface_integral!(du, mesh::TreeMesh{2}, equations, dg::DGSEM, cache)
    # FIXME: `surface_integral::SurfaceIntegralWeakForm`
    factor_arr = CuArray{Float32}([
                                      dg.basis.boundary_interpolation[1, 1],
                                      dg.basis.boundary_interpolation[size(du, 2), 2]
                                  ])
    surface_flux_values = CuArray{Float32}(cache.elements.surface_flux_values)

    size_arr = CuArray{Float32}(undef, size(du, 1), size(du, 2)^2, size(du, 4))

    surface_integral_kernel = @cuda launch=false surface_integral_kernel!(du, factor_arr,
                                                                          surface_flux_values,
                                                                          equations)
    surface_integral_kernel(du, factor_arr, surface_flux_values, equations;
                            configurator_3d(surface_integral_kernel, size_arr)...,)

    return nothing
end

# Pack kernels for applying Jacobian to reference element
function cuda_jacobian!(du, mesh::TreeMesh{2}, equations, cache)
    inverse_jacobian = CuArray{Float32}(cache.elements.inverse_jacobian)

    size_arr = CuArray{Float32}(undef, size(du, 1), size(du, 2)^2, size(du, 4))

    jacobian_kernel = @cuda launch=false jacobian_kernel!(du, inverse_jacobian, equations)
    jacobian_kernel(du, inverse_jacobian, equations;
                    configurator_3d(jacobian_kernel, size_arr)...)

    return nothing
end

# Dummy function returning nothing              
function cuda_sources!(du, u, t, source_terms::Nothing, equations::AbstractEquations{2},
                       cache)
    return nothing
end

# Put everything together into a single function 
# Ref: `rhs!` function in Trixi.jl

function rhs_gpu!(du_cpu, u_cpu, t, mesh::TreeMesh{2}, equations, initial_condition,
                  boundary_conditions, source_terms::Source, dg::DGSEM,
                  cache) where {Source}
    du, u = copy_to_device!(du_cpu, u_cpu)

    cuda_volume_integral!(du, u, mesh, have_nonconservative_terms(equations), equations,
                          dg.volume_integral, dg)

    cuda_prolong2interfaces!(u, mesh, cache)

    cuda_interface_flux!(mesh, have_nonconservative_terms(equations), equations, dg, cache)

    cuda_prolong2boundaries!(u, mesh, boundary_conditions, cache)

    cuda_boundary_flux!(t, mesh, boundary_conditions, equations, dg, cache)

    cuda_surface_integral!(du, mesh, equations, dg, cache)

    cuda_jacobian!(du, mesh, equations, cache)

    cuda_sources!(du, u, t, source_terms, equations, cache)

    du_computed, _ = copy_to_host!(du, u)
    du_cpu .= du_computed

    return nothing
end
