using RvSpectML
 using Statistics
 using Dates

make_plots = false
include("neid_solar_1_read.jl")
 order_list_timeseries = RvSpectML.make_order_list_timeseries(solar_data)
 order_list_timeseries = RvSpectML.filter_bad_chunks(order_list_timeseries,verbose=true)
 lambda_range_with_data = (min = maximum(d->minimum(d.λ),solar_data), max = minimum(d->maximum(d.λ),solar_data) )
 RvSpectML.normalize_spectra!(order_list_timeseries,solar_data);

espresso_filename = joinpath(pkgdir(RvSpectML),"data","masks","G2.espresso.mas")
 espresso_df = RvSpectML.read_linelist_espresso(espresso_filename)
 line_list_df = espresso_df |>
     @filter(lambda_range_with_data.min <= _.lambda ) |>
    @filter( _.lambda < lambda_range_with_data.max) |>
#    @filter( _.lambda < 6000.0 ) |>                       # Avoid tellurics at redder wavelengths
#    @filter( _.lambda >6157 || _.lambda < 6155  ) |>   # Avoid "line" w/ large variability
    DataFrame

# Setup to run CCF
mask_shape = RvSpectML.CCF.TopHatCCFMask(order_list_timeseries.inst, scale_factor=1.6)
 line_list = RvSpectML.CCF.BasicLineList(line_list_df.lambda, line_list_df.weight)
 ccf_plan = RvSpectML.CCF.BasicCCFPlan(mask_shape = mask_shape, line_list=line_list)
 v_grid = RvSpectML.CCF.calc_ccf_v_grid(ccf_plan)

# Compute CCF's & measure RVs
tstart = now()
 @time ccfs = RvSpectML.CCF.calc_ccf_chunklist_timeseries(order_list_timeseries, ccf_plan)
 println("# CCF runtime: ", now()-tstart)

make_plots = true
 rvs_ccf_gauss = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i],fit_type = "gaussian") for i in 1:length(order_list_timeseries) ]
 rvs_ccf_quad  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "quadratic") for i in 1:length(order_list_timeseries) ]
 rvs_ccf_cent  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "centroid") for i in 1:length(order_list_timeseries) ]
 rvs_ccf_best  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "bestfit") for i in 1:length(order_list_timeseries) ]
 println("RMS of RVs (ESPRESSO lines):  Gaussian: ",std(rvs_ccf_gauss), "   Quadratic: ", std(rvs_ccf_quad), "   Centroid: ", std(rvs_ccf_cent) )
 if make_plots
   using Plots
  plot(v_grid,ccfs,label=:none)
  xlabel!("v (m/s)")
  ylabel!("CCF")
 end

make_plots = true
 if make_plots
   t_idx = 1
   using Plots
   plot(v_grid,ccfs[:,t_idx],label=:none)
   xlabel!("v (m/s)")
   ylabel!("CCF")
 end


#make_plots = true
if make_plots
   nbin = 4
   plt_t = (order_list_timeseries.times .- minimum(order_list_timeseries.times) ) .* 24
   plt = scatter(plt_t,rvs_ccf_gauss.-mean(rvs_ccf_gauss),label="Gaussian")
   scatter!(plt,plt_t,rvs_ccf_quad.-mean(rvs_ccf_quad),label="Quadratic")
   #scatter!(plt,plt_t,rvs_ccf_best.-mean(rvs_ccf_best),label="Best fit")
   #scatter!(plt,plt_t,rvs_ccf_cent.mean(rvs_ccf_cent),label="Centroid")
   times_binned = RvSpectML.bin_times_consecutive(plt_t, nbin)
   rvs_ccf_gauss_binned = RvSpectML.bin_rvs_consecutive(rvs_ccf_gauss, nbin)
   rvs_ccf_quad_binned = RvSpectML.bin_rvs_consecutive(rvs_ccf_quad, nbin)
   rvs_ccf_cent_binned = RvSpectML.bin_rvs_consecutive(rvs_ccf_cent, nbin)
   println("# RMS of binned (n=",nbin,") RVs: ", std(rvs_ccf_gauss_binned), "  ", std(rvs_ccf_quad_binned), "  ", std(rvs_ccf_cent_binned))
   scatter!(times_binned,rvs_ccf_gauss_binned.-mean(rvs_ccf_gauss),label="Binned Gauss")
   scatter!(times_binned,rvs_ccf_quad_binned.-mean(rvs_ccf_quad),label="Binned Quad")
   #scatter!(times_binned,rvs_ccf_cent_binned.-mean(rvs_ccf_cent),label="Binned Cent")
   plot!(times_binned,rvs_ccf_gauss_binned.-mean(rvs_ccf_gauss),label=:none,color=3)
   plot!(times_binned,rvs_ccf_quad_binned.-mean(rvs_ccf_quad),label=:none,color=4)
   #plot!(times_binned,rvs_ccf_cent_binned.-mean(rvs_ccf_cent),label=:none,color=5)
   xlabel!(plt,"Time (hr)")
   ylabel!(plt,"RV (m/s)")
   display(plt)
 end

#=
# TODO: Need to update code below
# Try using Alex's clean lines
vald_filename = joinpath(ancilary_solar_data_path,"VALD_Fe1_DP_rejectTelluricSlope0.0_badLineFilterESPRESSO-strict-NEID-BIS_overlapcutoff6e-05_depthcutoff0.05_allowBlends0_wavesReiners_depthssolar_nbin1depth0.mas")
 vald_df = RvSpectML.read_mask_vald(vald_filename)
 ssn_out = RvSpectML.searchsortednearest(line_list_df.lambda,vald_df.lambda)
 line_list_clean = line_list_df[ssn_out,:]
 @assert maximum(line_list_clean.lambda .- vald_df.lambda) < 0.05
 clean_mask = hcat(line_list_clean.lambda./mask_entry_doppler_factor,line_list_clean.lambda.*mask_entry_doppler_factor, line_list_clean.weight)

 @time ccfs = RvSpectML.CCF.calc_ccf_chunklist_timeseries(order_list_timeseries, line_list, mask_shape=mask_shape, plan=ccf_plan)
  rvs_ccf_gauss = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i],fit_type = "gaussian") for i in 1:length(order_list_timeseries) ]
  rvs_ccf_quad  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "quadratic") for i in 1:length(order_list_timeseries) ]
  rvs_ccf_cent  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "centroid") for i in 1:length(order_list_timeseries) ]
  rvs_ccf_best  = [ RvSpectML.RVFromCCF.measure_rv_from_ccf(v_grid,ccfs[:,i], fit_type = "bestfit") for i in 1:length(order_list_timeseries) ]
  println("RMS of RVs (Alex's lines):  Gaussian: ",std(rvs_ccf_gauss), "   Quadratic: ", std(rvs_ccf_quad), "   Centroid: ", std(rvs_ccf_cent) )
  if make_plots
    using Plots
   plot(v_grid,ccfs,label=:none)
   xlabel!("Δv (m/s)")
   ylabel!("CCF")
  end

=#
