function convolutionalsample!(grid, gridspec, uvdata, kernel, width; uoffset=0, voffset=0)
    for uvdatum in uvdata
        upx, vpx = Pigi.lambda2px(uvdatum.u - uoffset, uvdatum.v - voffset, gridspec)

        for ypx in axes(grid, 2)
            dypx = abs(ypx - vpx)
            if 0 <= dypx <= width
                for xpx in axes(grid, 1)
                    dxpx = abs(xpx - upx)
                    if 0 <= dxpx <= width
                        grid[xpx, ypx] += kernel(sqrt(dxpx^2 + dypx^2)) * uvdatum.weights .* uvdatum.data
                    end
                end
            end
        end
    end
end

function idft!(dft, uvdata, gridspec, normfactor)
    rowscomplete = 0
    Threads.@threads for lmpx in CartesianIndices(dft)
        lpx, mpx = Tuple(lmpx)
        if lpx == size(dft)[2]
            rowscomplete += 1
            print("\r", rowscomplete / size(dft)[1] * 100)
        end

        l, m = Pigi.px2sky(lpx, mpx, gridspec)

        val = zero(SMatrix{2, 2, ComplexF64, 4})
        for uvdatum in uvdata
            val += uvdatum.data * exp(
                2π * 1im * (uvdatum.u * l + uvdatum.v * m + uvdatum.w * Pigi.ndash(l, m))
            )
        end
        dft[lpx, mpx] = val / normfactor
    end
end