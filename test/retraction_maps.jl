# Exponential
ϕ = @SVector rand(3)
@test ForwardDiff.jacobian(x->SVector(ExponentialMap(x)),ϕ) ≈ jacobian(ExponentialMap,ϕ)

ϕ = 1e-6*@SVector rand(3)
@test ForwardDiff.jacobian(x->SVector(ExponentialMap(x)),ϕ) ≈ jacobian(ExponentialMap,ϕ)


# MRPs
p = SVector(rand(MRP))

@test ForwardDiff.jacobian(x->SVector(MRPMap(x)),p) ≈
    jacobian(MRPMap, p)

# Gibbs Vectors
g = @SVector rand(3)
@test ForwardDiff.jacobian(x->SVector(CayleyMap(x)),g) ≈ jacobian(CayleyMap, g)

# Vector Part
v = 0.1*@SVector rand(3)
@test ForwardDiff.jacobian(x->SVector(VectorPart(x)),v) ≈
    jacobian(VectorPart, v)


jac_eye = [@SMatrix zeros(1,3); 0.5*Diagonal(@SVector ones(3))];
@test jacobian(ExponentialMap, p*1e-10) ≈ jac_eye
@test jacobian(MRPMap, p*1e-10) ≈ jac_eye
@test jacobian(CayleyMap, p*1e-10) ≈ jac_eye
@test jacobian(VectorPart, p*1e-10) ≈ jac_eye


############################################################################################
#                                 INVERSE RETRACTION MAPS
############################################################################################

# Exponential Map
Random.seed!(1);
q = rand(UnitQuaternion)
q = UnitQuaternion{ExponentialMap}(q)
qval = SVector(q)
@test ExponentialMap(q) == logm(q)
@test ExponentialMap(ExponentialMap(q)) ≈ q
@test ExponentialMap(ExponentialMap(ϕ)) ≈ ϕ

function invmap(q)
    v = @SVector [q[2], q[3], q[4]]
    s = q[1]
    θ = norm(v)
    M = 2atan(θ, s)/θ
    return M*v
end
@test invmap(qval) ≈ logm(q)

qI = VectorPart(v*1e-5)
@test ForwardDiff.jacobian(invmap, qval) ≈ jacobian(ExponentialMap, q)
@test ForwardDiff.jacobian(invmap, SVector(qI)) ≈ jacobian(ExponentialMap, qI)

# Vector Part
@test VectorPart(q) == 2*qval[2:4]
@test VectorPart(VectorPart(q)) ≈ q
@test VectorPart(VectorPart(v)) ≈ v

# Cayley
invmap(q) = 1/q[1] * 2*@SVector [q[2], q[3], q[4]]
@test CayleyMap(q) ≈ invmap(qval)
@test ForwardDiff.jacobian(invmap, qval) ≈ jacobian(CayleyMap, q)
@test CayleyMap(CayleyMap(q)) ≈ q
@test CayleyMap(CayleyMap(g)) ≈ g

# MRP
invmap(q) = 4/(1+q[1]) * @SVector [q[2], q[3], q[4]]
MRPMap(q) ≈ invmap(qval)
@test ForwardDiff.jacobian(invmap, qval) ≈ jacobian(MRPMap, q)
@test MRPMap(MRPMap(q)) ≈ q
@test MRPMap(MRPMap(p)) ≈ p


# Test near origin
jacT_eye = [@SMatrix zeros(1,3); 2*Diagonal(@SVector ones(3))]';
@test isapprox(jacobian(ExponentialMap,qI), jacT_eye, atol=1e-5)
@test isapprox(jacobian(VectorPart,qI), jacT_eye, atol=1e-5)
@test isapprox(jacobian(CayleyMap,qI), jacT_eye, atol=1e-5)
@test isapprox(jacobian(MRPMap,qI), jacT_eye, atol=1e-5)
