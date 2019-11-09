prob = copy(Problems.cartpole)
sprob = copy(Problems.cartpole_static)

ilqr = iLQRSolver(prob)
silqr = StaticiLQRSolver(sprob)

solve!(prob, ilqr)
plot(prob.X)


solve!(sprob, silqr)
Xs = state(sprob)
Us = control(sprob)
plot(Xs)
norm(Xs - prob.X)

U0 = [u0 for k = 1:prob.N-1]
@btime begin
    initial_controls!($prob, $U0)
    solve($prob,$ilqr)
end

x0 = sprob.x0
u0 = control(sprob)[1]
@btime begin
    for k = 1:$sprob.N
        $sprob.Z[k].z = [$x0*NaN; $u0]
    end
    solve!($sprob, $silqr)  # 55x speedup
end


# Now make augmented lagragian problem
prob = copy(Problems.cartpole)
sprob = copy(Problems.cartpole_static)
sprob2 = copy(Problems.cartpole_static)
u0 = control(sprob)[1]

al = AugmentedLagrangianSolver(prob)
prob_al = AugmentedLagrangianProblem(prob, al)

sopts = AugmentedLagrangianSolverOptions{Float64}()
sopts.opts_uncon = StaticiLQRSolverOptions()
reset!(sprob.constraints, sopts)
sal = StaticALSolver(sprob, sopts)
sprob_al = convertProblem(sprob, sal)

solve!(prob, al)
max_violation(prob)

solve!(sprob_al, sal)
max_violation(sprob_al)

for k = 1:sprob.N
    sprob_al.Z[k].z = [x0*NaN; u0]
end
reset!(sprob_al.obj.constraints, sopts)

solve!(sprob_al, sal)  # 55x speedup
max_violation(sprob_al)

@btime begin
    initial_controls!($prob, $U0)
    solve($prob,$al)
end

@btime begin
    for k = 1:$sprob.N
        $sprob_al.Z[k].z = [$x0*NaN; $u0]
    end
    reset!($sprob_al.obj.constraints, $sal.opts)
    solve!($sprob_al, $sal)  # 92x faster!!!
end

function myreset(solver::StaticALSolver{T,S}) where {T,S}
    solver_uncon = solver.solver_uncon::S
    reset!(solver_uncon)
end
@btime myreset($sal)
@btime reset!($sal.solver_uncon, false)


ilqr = iLQRSolver(prob_al)
silqr = StaticiLQRSolver(sprob_al)

solve!(prob_al, ilqr)
solve!(sprob_al, silqr)
norm(state(sprob_al) - prob_al.X)

for i = 1:10
    dual_update!(prob_al, al)
    penalty_update!(prob_al, al)

    dual_update!(sprob_al, sal)
    penalty_update!(sprob_al, sal)

    solve!(prob_al, ilqr)
    solve!(sprob_al, silqr)
end
norm(state(sprob_al) - prob_al.X)

ilqr.ρ[1]
silqr.ρ[1]

max_violation(al)
max_violation(sprob_al)


# Projected Newton
prob = copy(Problems.cartpole)
sprob = copy(Problems.cartpole_static)

ilqr = iLQRSolver(prob)
silqr = StaticiLQRSolver(sprob)

al = AugmentedLagrangianSolver(prob)
prob_al = AugmentedLagrangianProblem(prob, al)

sopts = AugmentedLagrangianSolverOptions{Float64}()
sopts.opts_uncon = StaticiLQRSolverOptions()
reset!(sprob.constraints, sopts)
sal = StaticALSolver(sprob, sopts)
sprob_al = convertProblem(sprob, sal)

# Solve with Augmented Lagrangian
solve!(prob, al)
solve!(sprob_al, sal)
max_violation(al)
max_violation(sprob_al)
state(sprob_al) ≈ prob.X
control(sprob_al) ≈ prob.U

# Finish with Projected Newton
pn = ProjectedNewtonSolver(prob)
spn = StaticPNSolver(sprob_al)

update_constraints!(prob, pn)
dynamics_constraints!(prob, pn)
update_constraints!(sprob_al, spn)
copy_constraints!(sprob_al, spn)
Vector(pn.y) ≈ spn.d

@btime begin
    update_constraints!($prob, $pn)
    dynamics_constraints!($prob, $pn)
end
@btime begin
    update_constraints!($sprob_al, $spn)
    copy_constraints!($sprob_al, $spn)
end  # 50x faster


dynamics_jacobian!(prob, pn)
constraint_jacobian!(prob, pn)
constraint_jacobian!(sprob_al, spn)
copy_jacobians!(sprob_al, spn)
pn.Y ≈ Matrix(spn.D)
Matrix(spn.D)
pn.Y .≈ spn.D
pn.y ≈ spn.d
@btime begin
    dynamics_jacobian!($prob, $pn)
    constraint_jacobian!($prob, $pn)
end

@btime begin
    constraint_jacobian!(sprob_al, spn)
    copy_jacobians!(sprob_al, spn)
end

active_constraints(sprob_al, spn)
@btime active_constraints($sprob_al, $spn)

@btime constraint_jacobian!($sprob_al, $spn)

E = CostExpansion(size(prob)...)
cost_expansion(E, sprob_al, spn)
@btime cost_expansion($E, $sprob_al, $spn)