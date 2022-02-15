using DataDrivenDiffEq
using ModelingToolkit
using LinearAlgebra
using OrdinaryDiffEq
using Test
#using Symbolics: scalarize

function cart_pole(u, p, t)
    du = similar(u)
    F = -0.2 + 0.5*sin(6*t) # the input
    du[1] = u[3]
    du[2] = u[4]
    du[3] = -(19.62*sin(u[1])+sin(u[1])*cos(u[1])*u[3]^2+F*cos(u[1]))/(2-cos(u[1])^2)
    du[4] = -(sin(u[1])*u[3]^2 + 9.81*sin(u[1])*cos(u[1])+F)/(2-cos(u[1])^2)
    return du
end

u0 = [0.3; 0; 1.0; 0]
tspan = (0.0, 5.0)
dt = 0.05
cart_pole_prob = ODEProblem(cart_pole, u0, tspan)
solution = solve(cart_pole_prob, Tsit5(), saveat = dt)

# Create the differential data
X = solution[:,:]
DX = similar(X)
for (i, xi) in enumerate(eachcol(X))
    DX[:, i] = cart_pole(xi, [], solution.t[i])
end
t = solution.t

ddprob = ContinuousDataDrivenProblem(
    X , t, DX = DX[3:4, :], U = (u,p,t) -> [-0.2 + 0.5*sin(6*t)]
)

@variables u[1:4] x[1:1] t
du = [Symbolics.variable("du", i) for i in 3:4]
u = collect(u)
du = collect(du)
x = collect(x)

polys = polynomial_basis(u, 2)
push!(polys, sin.(u[1]))
push!(polys, cos.(u[1]))
push!(polys, sin.(u[1])^2)
push!(polys, cos.(u[1])^2)
push!(polys, sin.(u[1]).*u[3:4]...)
push!(polys, sin.(u[1]).*u[3:4].^2...)
push!(polys, sin.(u[1]).*cos.(u[1])...)
push!(polys, sin.(u[1]).*cos.(u[1]).*u[3:4]...)
push!(polys, sin.(u[1]).*cos.(u[1]).*u[3:4].^2...)
implicits = [du;  du[1] .* u; du[2] .* u; du .* cos(u[1]);   du .* cos(u[1])^2; polys]
push!(implicits, x...)
push!(implicits, x[1]*cos(u[1]))
push!(implicits, x[1]*sin(u[1]))

basis= Basis(implicits, u, controls = x,  iv = t, implicits = du)

# Simply use any optimizer you would use for sindy
λ = [1e-4;5e-4;1e-3;2e-3;3e-3;4e-3;5e-3;6e-3;7e-3;8e-3;9e-3;1e-2;2e-2;3e-2;4e-2;5e-2]

opt = ImplicitOptimizer(λ)
# AICC
ĝ(x) = x[1] <= 1 ? Inf : 2*x[1]-2*log(x[2])
res = solve(ddprob, basis, opt,g = ĝ, maxiter = 1000, scale_coefficients = false, progress = false, normalize = false)

m = metrics(res)

@test length(parameters(res)) == 10
@test all(m[:L₂] .< 1e-2)
@test all(m[:AIC] .> 1000.0)
@test all(m[:R²] .> 0.9)
