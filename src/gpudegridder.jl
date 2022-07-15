function degridder!(workunits::AbstractVector{WorkUnit{T}}, grid::CuMatrix, subtaper::CuMatrix{T}, degridop) where T

    # A terms are shared amongst work units, so we only have to transfer over the unique arrays.
    # We do this (awkwardly) by hashing them into an ID dictionary.
    Aterms = IdDict{AbstractMatrix{SMatrix{2, 2, Complex{T}, 4}}, CuMatrix{SMatrix{2, 2, Complex{T}, 4}}}()
    for workunit in workunits, Aterm in (workunit.Aleft, workunit.Aright)
        if !haskey(Aterms, Aterm)
            Aterms[Aterm] = CuArray(Aterm)
        end
    end

    Base.@sync for workunit in workunits
        # We do the ifft in the default stream, due to garbage issues the fft when run on multiple streams.
        # Once this is done, we have off the rest of the work to a separate stream.
        CUDA.@sync begin
            subgrid = extractsubgrid(grid, workunit)

            fftshift!(subgrid)
            subgridflat = reinterpret(reshape, Complex{T}, subgrid)
            ifft!(subgridflat, (2, 3))
        end

        Base.@async CUDA.@sync begin
            # Apply A terms
            Aleft = Aterms[workunit.Aleft]
            Aright = Aterms[workunit.Aright]
            map!(subgrid, Aleft, subgrid, Aright, subtaper) do Aleft, subgrid, Aright, t
                return Aleft * subgrid * adjoint(Aright) * t
            end

            uvdata = (
                u=CuArray(workunit.data.u),
                v=CuArray(workunit.data.v),
                w=CuArray(workunit.data.w),
                data=CuArray(workunit.data.data)
            )
            gpudft!(uvdata, (u0=workunit.u0, v0=workunit.v0, w0=workunit.w0), subgrid, workunit.subgridspec, degridop)

            copyto!(workunit.data.data, uvdata.data)
        end
    end
end

function gpudft!(uvdata, origin, subgrid, subgridspec, degridop)
    function _gpudft!(uvdata, origin, subgrid::CuDeviceMatrix{SMatrix{2, 2, Complex{T}, 4}}, subgridspec, degridop) where T
        gpuidx = (blockIdx().x - 1) * blockDim().x + threadIdx().x
        stride = gridDim().x * blockDim().x

        lms = fftfreq(subgridspec.Nx, 1 / subgridspec.scaleuv)

        for idx in gpuidx:stride:length(uvdata.data)
            u, v, w = uvdata.u[idx], uvdata.v[idx], uvdata.w[idx]

            data = SMatrix{2, 2, Complex{T}, 4}(0, 0, 0, 0)
            for (mpx, m) in enumerate(lms), (lpx, l) in enumerate(lms)
                phase = -2im * T(π) * (
                    (u - origin.u0) * l +
                    (v - origin.v0) * m +
                    (w - origin.w0) * ndash(l, m)
                )
                data += subgrid[lpx, mpx] * exp(phase)
            end

            uvdata.data[idx] = degridop(uvdata.data[idx], data)
        end
    end

    kernel = @cuda launch=false _gpudft!(uvdata, origin, subgrid, subgridspec, degridop)
    config = launch_configuration(kernel.fun)
    threads = min(length(uvdata.data), config.threads)
    blocks = cld(length(uvdata.data), threads)
    kernel(uvdata, origin, subgrid, subgridspec, degridop; threads, blocks)
end