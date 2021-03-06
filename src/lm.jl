VM = Union{Vector{Float64},Matrix{Float64}}

immutable State_lm
  b::Vector{Float64}
  sig2::Float64
end

immutable LM
  post_params::Vector{State_lm}
  DIC::Float64
end

immutable Summary_lm
  mean_beta::Vector{Float64}
  std_beta::Vector{Float64}
  quantile_beta::Matrix{Float64}
  mean_sig::Float64
  std_sig::Float64
  quantile_sig::Vector{Float64}
  DIC::Float64
  B::Int
end

function show(io::IO, SL::Summary_lm)
  const P = length(SL.mean_beta)
  zeroInCI = [SL.quantile_beta[2,p] <= 0 <= SL.quantile_beta[6,p] ? "" : "*" for p in 1:P]

  @printf "%5s%10s%10s%3s\n" "" "mean" "std" "≠0"
  for k in 1:P
    @printf "%5s%10.4f%10.4f%3s\n" string("β",k-1) SL.mean_beta[k] SL.std_beta[k] zeroInCI[k]
  end
  @printf "%5s%10.4f%10.4f\n" "σ" SL.mean_sig SL.std_sig
  @printf "%5s%10.2f\n" "DIC" SL.DIC
end


function dic{T <: VM}(post_samples::Vector{State_lm}, 
                      y::Vector{Float64}, X::T; 
                      addIntercept=true)
  if addIntercept
    X::Matrix{Float64} = [ones(size(X,1)) X]
  end
  const (N,P) = size(X)

  function loglike(param)
    -N/2 * log(2pi*param.sig2) - sum((y - X*param.b).^2) / (2param.sig2)
  end

  dic(post_samples,loglike)
end


function cpo(model::LM, y::Vector{Float64}, X::Matrix{Float64})
  function den(p::State_lm, yi::Float64, xi::Vector{Float64}) 
    xb = xi'p.b
    assert(length(xb) == 1)
    # Declaring the types really speeds things up here
    return pdf(Normal(xb[1]::Float64, sqrt(p.sig2)::Float64), 
               yi::Float64)
  end
  cpo(model.post_params, den, y, X)
end


function summary(out::LM; alpha::Float64=.05)
  const post_beta= hcat(map(o -> o.b, out.post_params)...)'
  const (B,P) = size(post_beta)
  const mean_beta = vec(mean(post_beta,1))
  const std_beta = vec(std(post_beta,1))
  const quantile_beta = hcat([ quantile(post_beta[:,p], quants) for p in 1:P]...)
  const post_sig = map(o -> sqrt(o.sig2), out.post_params)
  const mean_sig = mean(post_sig)
  const std_sig = std(post_sig)
  const quantile_sig = quantile(post_sig, quants)

  return Summary_lm(mean_beta,std_beta,quantile_beta,
                    mean_sig,std_sig,quantile_sig,
                    out.DIC,B)
end

function lm{T <: VM}(y::Vector{Float64}, X::T; B::Int=10000, burn::Int=10, 
                     addIntercept::Bool=true)
  if addIntercept
    X = [ones(size(X,1)) X]
  end
  const (N,K) = size(X)
  const XXi = inv(X'X)
  const a = (N-K) / 2
  const BETA_HAT = XXi * X'y # use QR to do this instead?
  const beta_init = fill(0.0,K)
  const s2_init = 1.0

  function update(state::State_lm)
    const s2_new = rig(a, sum((y-X*state.b).^2)/2)
    const b_new = 
      rand(MultivariateNormal(BETA_HAT::Vector{Float64},
                              s2_new*XXi::Matrix{Float64}))
    State_lm(b_new,s2_new)
  end

  const post_params = MCMC.gibbs(State_lm(beta_init,s2_init), update, B, burn)
  const DIC = dic(post_params, y, X, addIntercept=false)

  LM(post_params,DIC)
end



#= For general covariance matrix
function lm(y:: Vector, X::Matrix, V::Matrix)
end
=#


#=
using BayesLM
n = 100
X = randn(n)
b = [0,3]
y = [ones(n) X] * b + randn(n)
@time model = lm(y,X);
summary(model)

using Distributions
@time cpo(model.post_params, cpo_f, [ones(n) X])
=#
