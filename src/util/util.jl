"""
Author: Eric Ford
Created: August 2020
Contact: https://github.com/eford/
"""

# Constants
const speed_of_light_mps = 299792458.0 # TODO: Update value

"""
   calc_doppler_factor(rv; v_perp)

Return the Doppler boost factor (non-relativistic) for rv in km/s.
"""
function calc_doppler_factor end

calc_doppler_factor(rv::Real) = one(rv) + rv/speed_of_light_mps
calc_doppler_factor(rv::Real, v_perp::Real) = (one(rv) + rv/speed_of_light_mps)/(one(rv) - (rv^2+v_perp^2)/speed_of_light_mps^2)

"""
   searchsortednearest(a<:AbstractVector, x::Real)
   searchsortednearest(a<:AbstractVector, x<:AbstractVector)

   Find the index of vector a where the value of a is closest to x.
   All vecotrs are assumed to already be sorted.

Credit: traktofon @ https://discourse.julialang.org/t/findnearest-function/4143/4
Vector Vector version by Christian Gilbertson?
"""
function searchsortednearest end

function searchsortednearest(a::AbstractVector{T} where T<:Real, x::Real)
   idx = searchsortedfirst(a,x)
   if (idx==1); return idx; end
   if (idx>length(a)); return length(a); end
   if (a[idx]==x); return idx; end
   if (abs(a[idx]-x) < abs(a[idx-1]-x))
      return idx
   else
      return idx-1
   end
end

function searchsortednearest(x::T, a::AbstractVector{T}) where T
    @warn "Did you mean to reverse the order of x and a?"
    return searchsortednearest(a, x)
end

function searchsortednearest(a::Vector{T} where T<:Real, x::Vector{T} where T<:Real)
   len_x = length(x)
   len_a = length(a)
   idxs = zeros(Int64, len_x)
   idxs[1] = searchsortednearest(a, x[1])
   for i in 2:len_x
	   idxs[i] = idxs[i-1] + searchsortednearest(view(a, idxs[i-1]:len_a), x[i]) - 1
   end
   return idxs
end




""" Return true if all elements of array are equal to each other. """
@inline function allequal(x::AbstractArray{T,1}) where {T<:Real}
    length(x) < 2 && return true
    e1 = x[1]
    i = 2
    @inbounds for i=2:length(x)
        x[i] == e1 || return false
    end
    return true
end