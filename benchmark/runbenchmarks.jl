using BenchmarkTools
using Pigi
using Profile
using InteractiveUtils: @code_warntype
using StaticArrays

println("Running benchmarks...")

#=
2021/11/09 : Nimbus
    Time (mean ± σ): 15.936 s ± 134.312 ms GC (mean ± σ): 0.00% ± 0.00%
    Memory estimate: 9.06 MiB, allocs estimate: 86217
=#
begin
    path = "../testdata/1215555160/1215555160.ms"
    mset = Pigi.MeasurementSet(path, chanstart=1, chanstop=192)
    b = @benchmark sum(1 for uvdatum in Pigi.read($mset)) evals=1 samples=3 seconds=60
    show(stdout, MIME"text/plain"(), b)
    println()
end

#=
2021/11/09 : Nimbus
    Time (mean ± σ): 12.186 s ± 2.400 s GC (mean ± σ): 6.05% ± 2.37%
    Memory estimate: 19.24 GiB, allocs estimate: 27066
=#
begin
    println("Reading mset...")
    path = "../testdata/1215555160/1215555160.ms"
    mset = Pigi.MeasurementSet(path, chanstart=1, chanstop=384)
    println("Mset opened...")
    uvdata = collect(Pigi.read(mset))
    println(typeof(uvdata))
    println("Done.")

    scalelm = sin(deg2rad(15 / 3600))
    gridspec = Pigi.GridSpec(4000, 4000, scalelm=scalelm)
    subgridspec = Pigi.GridSpec(64, 64, scaleuv=gridspec.scaleuv)
    padding = 8
    wstep = 10

    b = @benchmark Pigi.partition($uvdata, $gridspec, $subgridspec, $padding, $wstep, (l, m) -> 1) evals=1 samples=5 seconds=60
    show(stdout, MIME"text/plain"(), b)
    println()
end

#=
2021/11/09 : Nimbus
    Time (mean ± σ): 4.568 s ± 16.015 ms GC (mean ± σ): 0.00% ± 0.00%
    Memory estimate: 2.00 MiB, allocs estimate: 54
2021/11/25 : Nimbus
    Time (mean ± σ): 4.271 s ± 14.215 ms GC (mean ± σ): 0.00% ± 0.00%
    Memory estimate: 2.00 MiB, allocs estimate: 27
    Note: enabled @SIMD
=#
begin
    precision = Float64

    subgridspec = Pigi.GridSpec(128, 128, scaleuv=1.2)
    padding = 14

    visgrid = zeros(Complex{precision}, 4, 128, 128)
    visgrid[:, 1 + padding:end - padding, 1 + padding:end - padding] = rand(Complex{precision}, 4, 128 - 2 * padding, 128 - 2 * padding)

    uvdata = Pigi.UVDatum{precision}[]
    for vpx in axes(visgrid, 3), upx in axes(visgrid, 2)
        val = visgrid[:, upx, vpx]
        if !all(val .== 0)
            u, v = Pigi.px2lambda(upx, vpx, subgridspec)
            push!(uvdata, Pigi.UVDatum{precision}(
                0, 0, u, v, 0, [1 1; 1 1], val
            ))
        end
    end
    println("Gridding $(length(uvdata)) uvdatum")

    Aleft = ones(SMatrix{2, 2, Complex{precision}, 4}, 128, 128)
    Aright = ones(SMatrix{2, 2, Complex{precision}, 4}, 128, 128)

    taper = Pigi.mkkbtaper(subgridspec)

    subgrid = Pigi.Subgrid{precision}(
        0, 0, 0, 0, 0, subgridspec, Aleft, Aright, uvdata
    )

    b = @benchmark Pigi.gridder($subgrid) evals=1 samples=10 seconds=60
    show(stdout, MIME"text/plain"(), b)
    println()
end

#=
2021/11/30 : Nimbus
    Time (mean ± σ): 5.601 s ± 18.682 ms GC (mean ± σ): 0.00% ± 0.00%
    Memory estimate: 1.00 MiB, allocs estimate: 29
=#
begin
    precision = Float64
    subgridspec = Pigi.GridSpec(128, 128, scaleuv=1)

    Aleft = Aright = ones(SMatrix{2, 2, Complex{precision}, 4}, 128, 128)

    uvdata = Pigi.UVDatum{precision}[]
    for (upx, vpx) in eachcol(rand(2, 10000))
        upx, vpx = upx * 100 + 14, vpx * 100 + 14
        u, v = Pigi.px2lambda(upx, vpx, subgridspec)
        push!(uvdata, Pigi.UVDatum{precision}(
            0, 0, u, v, 0, [1 1; 1 1], [0 0; 0 0]
        ))
    end
    println("Degridding $(length(uvdata)) uvdatum")

    subgrid = Pigi.Subgrid{precision}(
        0, 0, 0, 0, 0, subgridspec, Aleft, Aright, uvdata
    )

    grid = rand(SMatrix{2, 2, Complex{precision}, 4}, 128, 128)
    b = @benchmark Pigi.degridder!($subgrid, $grid, Pigi.degridop_replace) evals=1 samples=10 seconds=60
    show(stdout, MIME"text/plain"(), b)
    println()
end