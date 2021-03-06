 using RvSpectML
 using DataFrames, Query
 using Statistics
 # order_list_timeseries = RvSpectML.filter_bad_chunks(order_list_timeseries,verbose=true)
 using Dates

make_plots = true
#include("neid_solar_1_read.jl")
# order_list_timeseries = RvSpectML.make_order_list_timeseries(solar_data)
# RvSpectML.normalize_spectra!(order_list_timeseries,solar_data);

espresso_filename = joinpath(pkgdir(RvSpectML),"data","masks","G2.espresso.mas")
  espresso_df = RvSpectML.read_linelist_espresso(espresso_filename)
  #lambda_range_with_data = (min = maximum(d->minimum(d.λ),solar_data), max = minimum(d->maximum(d.λ),solar_data) )
  line_list_df = espresso_df |>
      #@filter(lambda_range_with_data.min <= _.lambda ) |>
      #@filter( _.lambda < lambda_range_with_data.max) |>
      DataFrame


inst = RvSpectML.TheoreticalInstrument.TheoreticalInstrument1D()
 spec = RvSpectML.TheoreticalInstrument.generate_spectrum(line_list_df, inst)
 lambda_range_with_data = minimum(spec.λ):maximum(spec.λ)
 line_list_df = espresso_df |>
     @filter(minimum(lambda_range_with_data) <= _.lambda ) |>
     @filter( _.lambda < maximum(lambda_range_with_data) ) |>
     DataFrame

period = 30
 times = range(0.0, stop=0.5*period, length=9)
 rv_mean = -825
 Δ_rvs_true = 3.0 .* cos.(2π.*times./period)
 rvs_true = rv_mean .+ Δ_rvs_true
 @time spectra = RvSpectML.TheoreticalInstrument.generate_spectra_timeseries(times, line_list_df, inst, rvs_true, snr_per_pixel=1000)

lambda_range_with_data = (min = maximum(d->minimum(d.λ),spectra), max = minimum(d->maximum(d.λ),spectra) )
 espresso_mask_df = RvSpectML.read_mask_espresso(espresso_filename)
 chunk_list_df = espresso_mask_df |>
  @filter(lambda_range_with_data.min <= _.lambda ) |>
  @filter( _.lambda < lambda_range_with_data.max) |>
  DataFrame

find_overlapping_chunks(chunk_list_df)
chunk_list_df = RvSpectML.merge_chunks(chunk_list_df)
  #@assert find_overlapping_chunks(chunk_list_df) == nothing


order_list_timeseries = RvSpectML.make_chunk_list_timeseries(spectra, chunk_list_df)

order_list_timeseries = RvSpectML.filter_bad_chunks(order_list_timeseries,verbose=true)
#RvSpectML.normalize_spectra!(order_list_timeseries,spectra);


# Setup to run CCF
mask_shape = RvSpectML.CCF.TopHatCCFMask(order_list_timeseries.inst, scale_factor=1.8) # 1.6)
  line_list = RvSpectML.CCF.BasicLineList(line_list_df.lambda, line_list_df.weight)
  ccf_plan = RvSpectML.CCF.BasicCCFPlan(mask_shape = mask_shape, line_list=line_list)
  v_grid = RvSpectML.CCF.calc_ccf_v_grid(ccf_plan)

# Compute CCF's & measure RVs
tstart = now()
 ccfs = RvSpectML.CCF.calc_ccf_chunklist_timeseries(order_list_timeseries, ccf_plan)
 println("# CCF runtime: ", now()-tstart)

#plot(v_grid,ccfs)
using Plots
rvs_ccf_gauss = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i],fit_type = "gaussian") for i in 1:length(order_list_timeseries) ]
 plot(times, rvs_ccf_gauss.-mean(rvs_ccf_gauss))
 rvs_ccf_quad = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i],fit_type = "quadratic") for i in 1:length(order_list_timeseries) ]
 println(" # RV mean: ", mean(rvs_ccf_gauss), "  max-min: ", maximum(rvs_ccf_gauss)-minimum(rvs_ccf_gauss) )
 plot!(times, rvs_ccf_quad.-mean(rvs_ccf_quad))

# Store estimated RVs in metadata
rvs_comp = rvs_ccf_gauss
 oversample_factor = 1
 oversample_fac_orders = 1
 map(i->order_list_timeseries.metadata[i][:rv_est] = rvs_comp[i]-mean(rvs_comp), 1:length(order_list_timeseries) )

@time ( spectral_orders_matrix, f_mean, var_mean, deriv, deriv2 )  = RvSpectML.make_template_spectra(order_list_timeseries)


order_grids = map(c->RvSpectML.make_grid_for_chunk(order_list_timeseries,c,oversample_factor=oversample_fac_orders, remove_rv_est=false), 1:num_chunks(order_list_timeseries) )
 start = now()
 @time ( spectral_orders_matrix, f_mean, var_mean, deriv, deriv2 )  = RvSpectML.pack_chunk_list_timeseries_to_matrix(order_list_timeseries,order_grids, alg=:TemporalGP ) # :Linear)
 println("# Pack into matrix runtime: ", now()-tstart)
 order_grids_2 = map(c->RvSpectML.make_grid_for_chunk(order_list_timeseries,c,oversample_factor=oversample_fac_orders, remove_rv_est=false), 1:num_chunks(order_list_timeseries) )
 @time ( spectral_orders_matrix_2, f_mean_2, var_mean_2, deriv_2, deriv2_2 ) = RvSpectML.pack_chunk_list_timeseries_to_matrix(order_list_timeseries,order_grids_2, alg=:Linear) # TemporalGP, smooth_factor=1.0)
 #order_grids_2 = map(c->RvSpectML.make_grid_for_chunk(order_list_timeseries,c,oversample_factor=oversample_fac_orders, remove_rv_est=true), 1:num_chunks(order_list_timeseries) )
 #@time spectral_orders_matrix_2 = RvSpectML.pack_shifted_chunk_list_timeseries_to_matrix(order_list_timeseries,order_grids_2, alg=:Linear)
 order_grids_3 = map(c->RvSpectML.make_grid_for_chunk(order_list_timeseries,c,oversample_factor=oversample_fac_orders, remove_rv_est=true), 1:num_chunks(order_list_timeseries) )
 @time ( spectral_orders_matrix_3, f_mean_3, var_mean_3, deriv_3, deriv2_3 ) = RvSpectML.pack_shifted_chunk_list_timeseries_to_matrix(order_list_timeseries,order_grids_3, alg=:TemporalGP, smooth_factor=4.0)

 #f_mean = calc_mean_spectrum(spectral_orders_matrix.flux,spectral_orders_matrix.var)
 #deriv = calc_mean_dfluxdlnlambda(spectral_orders_matrix.flux,spectral_orders_matrix.var,spectral_orders_matrix.λ,spectral_orders_matrix.chunk_map)
(rvs_1, σ_rvs_1) = RvSpectML.calc_rvs_from_taylor_expansion(spectral_orders_matrix,mean=f_mean,deriv=deriv)
 #f_mean_2 = calc_mean_spectrum(spectral_orders_matrix_2.flux,spectral_orders_matrix_2.var)
 #deriv_2 = calc_mean_dfluxdlnlambda(spectral_orders_matrix_2.flux,spectral_orders_matrix_2.var,spectral_orders_matrix_2.λ,spectral_orders_matrix_2.chunk_map)
(rvs_2, σ_rvs_2) = RvSpectML.calc_rvs_from_taylor_expansion(spectral_orders_matrix_2,mean=f_mean_2,deriv=deriv_2)
 #f_mean_3 = calc_mean_spectrum(spectral_orders_matrix_3.flux,spectral_orders_matrix_3.var)
 #deriv_3 = calc_mean_dfluxdlnlambda(spectral_orders_matrix_3.flux,spectral_orders_matrix_3.var,spectral_orders_matrix_3.λ,spectral_orders_matrix_3.chunk_map)
 #deriv2_3 = calc_mean_d2fluxdlnlambda2(spectral_orders_matrix_3.flux,spectral_orders_matrix_3.var,spectral_orders_matrix_3.λ,spectral_orders_matrix_3.chunk_map)
 (rvs_3, σ_rvs_3) = RvSpectML.calc_rvs_from_taylor_expansion(spectral_orders_matrix_3,mean=f_mean_3,deriv=deriv_3)#,deriv2=deriv2_3)
 #println("rvs_3 = [ ", rvs_3[1:3], ", ... ", "σ_rvs_3 = [ ", σ_rvs_3[1:3], ", ... ", )
 flush(stdout)
 println("oversample factor: ", oversample_fac_orders, "  RMS RVs_1: ", std(rvs_1), "   RMS RV_2: ", std(rvs_2), "  RMS RV_3: ", std(rvs_3) )
 println("oversample factor: ", oversample_fac_orders,  "  RMS RVs_1: ", std(rvs_1.-mean(rvs_1).-Δ_rvs_true),
                                                        "   RMS RV_2: ", std(rvs_2.-mean(rvs_2).-Δ_rvs_true),
                                                        "  RMS RV_3: ", std(rvs_3.-mean(rvs_3).-0.0.*Δ_rvs_true) )

plot(rvs_1.-mean(rvs_1).-0.0.*Δ_rvs_true, label="Δrv 1")

plot!((rvs_2.-mean(rvs_2)).-Δ_rvs_true, label="Δrv 2")
 plot!(rvs_3.-mean(rvs_3).-0.0.*Δ_rvs_true, label="Δrv 3")
 plot!((rvs_ccf_gauss.-mean(rvs_ccf_gauss)).-Δ_rvs_true, label="Δrv CCF gauss")
 #plot!((rvs_ccf_quad.-mean(rvs_ccf_quad)).-Δ_rvs_true, label="Δrv CCF quad")


idx_plot = 1000:1500
plot(f_mean[idx_plot])
plot(f_mean_2[idx_plot].-f_mean[idx_plot])
scatter!(f_mean_3[idx_plot].-f_mean[idx_plot], markersize=1.5)

scatter(deriv_2[idx_plot],deriv[idx_plot].-deriv_2[idx_plot], markersize=1.5)
scatter(deriv2_2[idx_plot],deriv2[idx_plot], markersize=1.5)
plot!(deriv_3[idx_plot].-deriv[idx_plot], markersize=1.5)

length(f_mean), length(f_mean_2), length(f_mean_3)

#plot!(f_mean_3)
f_mean_2
scatter(times,Δ_rvs_true,label="RV_true")
 plot!(times,rvs_1.-mean(rvs_1),label="RVs 1")
 scatter!(times,rvs_2.-mean(rvs_2),label="RVs 2")
 plot!(times,rvs_3.-mean(rvs_3),label="RVs 3")

using Plots
scatter(times,rvs_1.+Δ_rvs_true,label="RV_comp - RV_true")

plot()
 scatter!(Δ_rvs_true,rvs_comp.-mean(rvs_comp).-Δ_rvs_true)
 plot!(Δ_rvs_true,rvs_3, label="Δrv")


plot()
 xlims!(1,500)
 #plot((f_mean_3.-mean(f_mean_3))./std(f_mean_3), label="mean")
 #plot!(deriv_3./std(deriv_3), label="dfdlnλ")
 #plot!(deriv2_3./std(deriv2_3), label="d2fdlnλ2")


deriv2_3

plot(spectral_orders_matrix_2.λ[1:300],spectral_orders_matrix_2.flux[1:300,1],markersize=1.5)
plot!(spectral_orders_matrix.λ[1:300],spectral_orders_matrix.flux[1:300,1],markersize=1.5)


spectral_orders_matrix_2.flux
spectral_orders_matrix_2.λ[1:1000]


using Plots
size(spectral_orders_matrix.flux)
idx_plt = 52000:53000
idx_t = 5
plot(RvSpectML.get_λs(order_grids,idx_plt),spectral_orders_matrix.flux[idx_plt,idx_t])
plot!(RvSpectML.get_λs(order_grids_2,idx_plt),spectral_orders_matrix_2.flux[idx_plt,idx_t])
0
maximum(abs.(RvSpectML.get_λs(order_grids,idx_plt).-RvSpectML.get_λs(order_grids_2,idx_plt)))*RvSpectML.speed_of_light_mps
0
plot(RvSpectML.get_λs(order_grids,idx_plt),(RvSpectML.get_λs(order_grids_2,idx_plt).-RvSpectML.get_λs(order_grids,idx_plt))./

spectral_orders_matrix.flux

0
#=



 if 2 <= num_spectra_to_bin <=20
     spectral_orders_matrix = RvSpectML.bin_consecutive_spectra(spectral_orders_matrix,num_spectra_to_bin)
   end
   f_mean_orders = calc_mean_spectrum(spectral_orders_matrix.flux,spectral_orders_matrix.var)
   deriv_orders = calc_mean_dfluxdlnlambda(spectral_orders_matrix.flux,spectral_orders_matrix.var,spectral_orders_matrix.λ,spectral_orders_matrix.chunk_map)

 if make_plots
   plt_order = 40
   plt_order_pix = 3501:3800
   idx_plt = spectral_orders_matrix.chunk_map[plt_order][plt_order_pix]
   plt_λ = RvSpectML.get_λs(order_grids, idx_plt)
      mean_in_plt = mean(f_mean_orders[idx_plt])
      std_in_plt = stdm(f_mean_orders[idx_plt],mean_in_plt)
      local plt = plot()
      plot!(plt,plt_λ,(f_mean_orders[idx_plt].-mean_in_plt)./std_in_plt,label=:none,linecolor=:black)
      plot!(plt,plt_λ, deriv_orders[idx_plt]./std(deriv_orders[idx_plt]),label=:none, linecolor=:green)
      #scatter!(plt,plt_λ,(spectral_orders_matrix.flux[idx_plt,:].-mean_in_plt)./std_in_plt,markersize=1, label=:none)
      xlabel!(plt,"λ (Å)")
      ylabel!(plt,"Mean & Deriv")
      local plt3 = scatter(plt_λ,spectral_orders_matrix.flux[idx_plt,:].-f_mean_orders[idx_plt],markersize=1, label=:none)
      ylabel!(plt3,"Residuals")
      local pltall = plot(plt,plt3,layout=(2,1))
      display(pltall)
 end

 println("Computing RVs using dflux/dlnlambda from orders.")
   order_rvs = RvSpectML.calc_chunk_rvs_from_taylor_expansion(spectral_orders_matrix,mean=f_mean_orders,deriv=deriv_orders)
   ave_order_rvs = vec( sum(mapreduce(c ->order_rvs[c].rv./order_rvs[c].σ_rv.^2, hcat, 1:length(order_rvs)),dims=2) ./
                      sum(mapreduce(c ->(1.0./order_rvs[c].σ_rv.^2), hcat, 1:length(order_rvs)),dims=2) )
   rms_order_rvs = map(order->std(order.rv), order_rvs)
   mean_order_σrvs = map(order->mean(order.σ_rv), order_rvs)
   flush(stdout)
   println("# rms(ave_order_rvs)/√N = ", std(ave_order_rvs)/sqrt(length(ave_order_rvs)), "  <RMS RVs> = ", mean(rms_order_rvs)#=/sqrt(length(ave_order_rvs))=#, "  <σ_RVs> = ", mean(mean_order_σrvs) )
   if make_plots
     plt4 = histogram(abs.(ave_order_rvs),bins=40,label="|Ave Order RVs|", alpha=0.75)
     histogram!(plt4,rms_order_rvs,bins=40,label="RMS Order RVs", alpha=0.75)
     histogram!(plt4,mean_order_σrvs,bins=40,label="σ Order RVs", alpha=0.75)
     xlabel!("(m/s)")
     ylabel!("Counts")
   end

 chunk_rms_cut_off = quantile(rms_order_rvs,0.9)
   idx_good_chunks = findall(x-> x<= chunk_rms_cut_off, rms_order_rvs)
   @assert length(idx_good_chunks)>=1
   ave_good_chunks_rvs = vec( sum(mapreduce(c ->order_rvs[c].rv./order_rvs[c].σ_rv.^2, hcat, idx_good_chunks),dims=2) ./
                       sum(mapreduce(c ->(1.0./order_rvs[c].σ_rv.^2), hcat, idx_good_chunks),dims=2) )
   sigma_good_chunks_rvs = sqrt.(vec( sum(mapreduce(c ->1.0./order_rvs[c].σ_rv.^2, hcat, idx_good_chunks),dims=2) ./
                       sum(mapreduce(c ->(1.0./order_rvs[c].σ_rv.^4), hcat, idx_good_chunks),dims=2) ))

  rms_rvs_ave_good_orders = std(ave_good_chunks_rvs)
  mean_sigma_good_chunks = mean(sigma_good_chunks_rvs)
  flush(stdout)
  println("# rms(RVs_good_orders) = ", rms_rvs_ave_good_orders,  "  <σ_RV good orders> = ", mean_sigma_good_chunks, "   N_obs = ", length(ave_good_chunks_rvs) )
  #map(o->plot!(plt,chunk_list_timeseries.times,order_rvs[o].rv,yerr=order_rvs[o].σ_rv,markersize=1,label=:none),idx_good_chunks )

 if make_plots
    plt = plot()
    scatter!(plt,plt_times, rvs_1, yerr=σ_rvs_1, label="Equal weighted chunks", markersize=3, color=:blue, legend=:topleft)
    scatter!(plt,plt_times, ave_order_rvs,label="Ave Order RVs", markersize=3, color=:green)
    scatter!(plt,plt_times, ave_good_chunks_rvs, yerr=sigma_good_chunks_rvs, label="Ave good chunks", markersize=3, color=:red)
    xlabel!("Time (hours)")
    ylabel!("RV (m/s)")
    display(plt)
 end
=#
