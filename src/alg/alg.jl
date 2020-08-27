include("interp/interp.jl")
export pack_chunk_list_timeseries_to_matrix

include("calc_rv/project_flux.jl")
export calc_mean_spectrum, calc_dfluxdlnlambda, calc_mean_dfluxdlnlambda
export calc_rvs_from_taylor_expansion, calc_chunk_rvs_from_taylor_expansion
export compute_spectra_perp_doppler_shift

#include("calc_rv/ccf_std.jl")


#incldue("ccf.jl")    # TODO:  Need to fold into this package, adjust types, and add test/example
#include("ppca.jl")       # TODO:  Need to fold into this package, adjust types, and add test/example
