using TrajectoryOptimization
using ALTRO
using RobotDynamics
using BenchmarkTools
using ForwardDiff
using Test
using SparseArrays
using LinearAlgebra
const TO = TrajectoryOptimization

using TrajectoryOptimization: StaticKnotPoint
using TrajectoryOptimization: num_vars, TrajData, NLPTraj, TrajOptNLP, NLPConstraintSet,
    JacobianStructure, NLPData

# Test NLPTraj iteration
n,m,N = 3,2,101
NN = num_vars(n,m,N)
@test NN == N*n + (N-1)*m
Z0 = Traj(n,m,0.1,N)
Zdata = TrajData(Z0)
Z = rand(NN)
Z_ = NLPTraj(Z,Zdata)
@test Z_[1] isa StaticKnotPoint
@test state(Z_[2]) == Z[(n+m) .+ (1:n)]
@test state(Z_[end]) == Z[end-n+1:end]
@test length(Z_) == N
@test size(Z_) == (N,)
@test [z for z in Z_] isa Vector{<:StaticKnotPoint}
@test eltype(Z_) == StaticKnotPoint{n,m,Float64,n+m}

# Test with problem
prob = Problems.DubinsCar(:parallel_park)[1]
TO.add_dynamics_constraints!(prob)
n,m,N = size(prob)
cons = prob.constraints
NN = N*n + (N-1)*m
P = sum(TO.num_constraints(prob))

# Jacobian structure
jac = JacobianStructure(cons)
TO.get_inds(cons[2],n,m)
TO.widths(cons[end])
@test jac.cinds[1][1] == 1:n
@test jac.cinds[2][1] == n .+ (1:4)
@test jac.cinds[5][1] == (n+4) .+ (1:n)
@test jac.cinds[5][end] == P-2n+1:P-n
@test jac.cinds[4][1] == P-n+1:P
@test jac.zinds[1][1] == 1:n
@test jac.zinds[2][1] == 1:n+m
@test jac.zinds[5][1] == 1:n+m
@test jac.zinds[5][1,2] == (n+m) .+ (1:n)
@test jac.zinds[5][end,1] == NN-2n-m+1:NN-n
@test jac.zinds[5][end,2] == NN-n+1:NN
@test jac.zinds[4][1] == NN-n+1:NN
@test jac.linds[1][1] == 1:n^2
@test jac.linds[2][1] == n^2 .+ (1:4*(n+m))
@test jac.linds[5][1] == (n^2 + 4*(n+m)) .+ (1:n*(n+m))

D = spzeros(P,NN)
TO.jacobian_structure!(D, jac)
@test D[1:n,1:n] == reshape(1:n^2,n,n)
@test Matrix(D[n .+ (1:4), 1:n+m]) == n^2 .+ reshape(1:4*(n+m), 4, n+m)
@test nnz(D) == D[end,end]

Dv = zeros(nnz(D))
d = zeros(P)
C,c = TO.gen_convals(Dv,d,cons)
@test C[1][1].parent.indices == (1:n^2,)

D = spzeros(P,NN)
C,c = TO.gen_convals(D,d,cons)
@test C[1][1].indices == (1:n,1:n)


# Test second-order constraint term
data = NLPData(NN, P, jac.nD)
conSet = NLPConstraintSet(prob.model, prob.constraints, data)
prob.Z[2].z += rand(n+m)
conSet.λ[5][1] .= rand(n)
TO.evaluate!(conSet, prob.Z)
@test conSet.convals[end].vals[1] != zeros(n)
@test conSet.convals[end].vals[3] == zeros(n)
TO.∇jacobian!(conSet.hess, conSet, prob.Z, conSet.λ)
@test conSet.hess[end][1] != zeros(n+m,n+m)
@test conSet.hess[end][2] == zeros(n+m,n+m)

# Build NLP
nlp = TrajOptNLP(prob)
Zdata = nlp.Z.Zdata
@test states(nlp) ≈ states(prob.Z)
@test controls(nlp) ≈ controls(prob.Z)

Z_ = NLPTraj(prob.Z)
Z = Z_.Z
@test Z_[10].z == prob.Z[10].z
z = StaticKnotPoint(Z,Zdata,1)
@test state(z) ≈ state(prob.Z[1])


# Cost functions
@test cost(prob) ≈ TO.eval_f(nlp, Z)

@test TO.grad_f!(nlp, Z) ≈ ForwardDiff.gradient(x->TO.eval_f(nlp,x), Z)
# @btime TO.grad_f!($nlp, $Z)
# @btime ForwardDiff.gradient(x->TO.eval_f($nlp,x), $Z)

G = ForwardDiff.hessian(x->TO.eval_f(nlp,x), Z)
G0 = nlp.data.G
G0 .*= 0
@test TO.hess_f!(nlp, Z) ≈ G
@test nlp.E.cost[1].Q.parent === G0
# @btime TO.hess_f!($nlp, $Z)
# @btime ForwardDiff.hessian(x->TO.eval_f($nlp,x), $Z)

# Constraint Functions
initial_trajectory!(nlp, prob.Z)
al = AugmentedLagrangianSolver(prob)
max_violation(al)
TO.evaluate!(nlp.conSet, prob.Z)
c_max = max_violation(nlp.conSet)
@test c_max ≈ max_violation(al)

c = TO.eval_c!(nlp, Z)
@test max_violation(nlp) ≈ c_max
# @btime eval_c!($nlp, $Z)
# @btime evaluate!($nlp.conSet, $(prob.Z))

TO.jac_c!(nlp, Z)
D = nlp.data.D
@test D[1:n,1:n] == I(n)
@test D[end-n+1:end,end-n+1:end] == I(n)
@test D[end-2n+1:end-n,end-n+1:end] == -I(n)

# @btime jac_c!($nlp, $Z)

# Test Hessian lagrangian
nlp.conSet.λ[end][1] .= 0
@test TO.hess_L!(nlp, Z) ≈ G
nlp.conSet.λ[end][1] .= rand(n)
@test !(TO.hess_L!(nlp, Z) ≈ G)

# Test cost hessian structure
@test nlp.obj isa Objective{<:TO.DiagonalCostFunction}
G_ = TO.hess_f_structure(nlp)
@test nnz(G_) == NN
@test diag(G_) == 1:NN

obj_ = TO.QuadraticObjective(n,m,N)
prob_ = Problem(prob, obj=obj_)
nlp_ = TrajOptNLP(prob_)
@test !(nlp_.obj isa Objective{<:TO.DiagonalCostFunction})
G_ = TO.hess_f_structure(nlp_)
@test nnz(G_) == (N-1)*(n+m)^2 + n^2
@test G_[1:n+m, 1:n+m] == reshape(1:(n+m)^2, n+m, n+m)

r,c = TO.get_rc(G_)
@test [G_[r[i], c[i]] for i = 1:nnz(G_)] == 1:nnz(G_)


# Test jacobian structure
D_ = TO.jacobian_structure(nlp)
Matrix(D_)

@test D_[1:n,1:n] == reshape(1:n^2, n,n)
@test D_[n .+ (1:4), 1:n+m] == reshape(9 .+ (1:(n+m)*4), 4, n+m)
nlp.data.D .= 0
TO.jac_c!(nlp, Z)

nlp_ = TrajOptNLP(prob, jac_type=:vector)
D_ = TO.jacobian_structure(nlp_)
@test D_[1:n,1:n] == reshape(1:n^2, n,n)
@test D_[n .+ (1:4), 1:n+m] == reshape(9 .+ (1:(n+m)*4), 4, n+m)

nlp_ = TrajOptNLP(prob, remove_bounds=true, jac_type=:vector)
D_ = TO.jacobian_structure(nlp_)
@test D_[1:n,1:2n+m] == reshape(1:(2n+m)n, n, 2n+m)
@test Matrix(D_[n .+ (1:n), (n+m) .+ (1:2n+m)]) ≈ reshape((2n+m)n .+ (1:(2n+m)n), n, 2n+m)
@test nnz(D_) == (N-1)*(2n+m)*n

# Constraint type
IE = TO.constraint_type(nlp)
@test IE[1:n] == ones(n)             # initial state constraint
@test IE[n .+ (1:4)] == zeros(4)     # bound constraint
@test IE[(n+4) .+ (1:n)] == ones(n)  # dynamics constraint

cL,cU = TO.constraint_bounds(nlp)
@test cL[1:n] == zeros(n)
@test cL[n .+ (1:4)] == fill(-Inf,4)     # bound constraint
@test cL[(n+4) .+ (1:n)] == zeros(n)  # dynamics constraint
@test all(cU .== 0 )

# Test bounds removal
cons = prob.constraints
zL = fill(-Inf,NN)
zU = fill(+Inf,NN)
TO.primal_bounds!(zL, zU, cons, false)
@test zL[1:n] == zeros(n)
@test zU[1:n] == zeros(n)
@test zL[n+1:n+m] == fill(-2,m)
@test zU[n+m+1:2n+m] == [0.25, 1.501, Inf]
@test zL[n+m+1:2n+m] == [-0.25, -0.001, -Inf]
@test zL[end-n+1:end] == zeros(n)
@test zU[end-n+1:end] == zeros(n)

@test length(cons) == 5
cons2 = copy(cons)
TO.primal_bounds!(zL, zU, cons2, true)
@test length(cons2) == 1
@test cons2[1] isa TO.DynamicsConstraint
@test length(cons) == 5

prob = Problems.DubinsCar(:parallel_park)[1]
TO.add_dynamics_constraints!(prob)
n,m,N = size(prob)
cons = prob.constraints

nlp = TrajOptNLP(prob, remove_bounds=true)
@test length(prob.constraints) == 5  # make sure it doesn't modify the problem
@test length(nlp.conSet.convals) == 1
@test (zL,zU) == TO.primal_bounds!(nlp)


# Test vector sparsity
nlp_ = TrajOptNLP(prob, remove_bounds=true, jac_type=:vector)
TO.jac_c!(nlp_)
@test nlp_.conSet.convals[end].jac[1].parent.parent == nlp_.data.v
@test nlp_.data.v[1:n*(n+m)] == vec(nlp.data.D[1:n, 1:n+m])
TO.primal_bounds!(nlp_)
