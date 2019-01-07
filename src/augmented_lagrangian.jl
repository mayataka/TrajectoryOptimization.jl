"""
$(SIGNATURES)
    Lagrange multiplier updates
        -see Bertsekas 'Constrained Optimization' chapter 2 (p.135)
        -see Toussaint 'A Novel Augmented Lagrangian Approach for Inequalities and Convergent Any-Time Non-Central Updates'
"""
function λ_update!(results::ConstrainedIterResults,solver::Solver)
    n,m,N = get_sizes(solver)
    p,pI,pE = get_num_constraints(solver)
    p_N,pI_N,pE_N = get_num_terminal_constraints(solver)

    for k = 1:N-1
        results.λ[k] = max.(solver.opts.dual_min, min.(solver.opts.dual_max, results.λ[k] + results.Iμ[k]*results.C[k]))
        results.λ[k][1:pI] = max.(0.0,results.λ[k][1:pI])
    end

    results.λ[N] = max.(solver.opts.dual_min, min.(solver.opts.dual_max, results.λ[N] + results.Iμ[N]*results.C[N]))
    results.λ[N][1:pI_N] = max.(0.0,results.λ[N][1:pI_N])
end

""" @(SIGNATURES) Penalty update """
function μ_update!(results::ConstrainedIterResults,solver::Solver)
    if solver.opts.outer_loop_update_type == :default
        μ_update_default!(results,solver)
    elseif solver.opts.outer_loop_update_type == :individual
        μ_update_individual!(results,solver)
    end
    return nothing
end

""" @(SIGNATURES) Penalty update scheme ('default') - all penalty terms are updated"""
function μ_update_default!(results::ConstrainedIterResults,solver::Solver)
    n,m,N = get_sizes(solver)
    for k = 1:N
        results.μ[k] = min.(solver.opts.penalty_max, solver.opts.penalty_scaling*results.μ[k])
    end
    return nothing
end

""" @(SIGNATURES) Penalty update scheme ('individual')- all penalty terms are updated uniquely according to indiviual improvement compared to previous iteration"""
function μ_update_individual!(results::ConstrainedIterResults,solver::Solver)
    n,m,N = get_sizes(solver)
    p,pI,pE = get_num_constraints(solver)
    p_N,pI_N,pE_N = get_num_terminal_constraints(solver)

    constraint_decrease_ratio = solver.opts.constraint_decrease_ratio
    penalty_max = solver.opts.penalty_max
    penalty_scaling_no  = solver.opts.penalty_scaling_no
    penalty_scaling = solver.opts.penalty_scaling

    # Stage constraints
    for k = 1:N-1
        for i = 1:p
            if p <= pI
                if max(0.0,results.C[k][i]) <= constraint_decrease_ratio*max(0.0,results.C_prev[k][i])
                    results.μ[k][i] = min(penalty_max, penalty_scaling_no*results.μ[k][i])
                else
                    results.μ[k][i] = min(penalty_max, penalty_scaling*results.μ[k][i])
                end
            else
                if abs(results.C[k][i]) <= constraint_decrease_ratio*abs(results.C_prev[k][i])
                    results.μ[k][i] = min(penalty_max, penalty_scaling_no*results.μ[k][i])
                else
                    results.μ[k][i] = min(penalty_max, penalty_scaling*results.μ[k][i])
                end
            end
        end
    end

    k = N
    for i = 1:p_N
        if p_N <= pI_N
            if max(0.0,results.C[k][i]) <= constraint_decrease_ratio*max(0.0,results.C_prev[k][i])
                results.μ[k][i] = min(penalty_max, penalty_scaling_no*results.μ[k][i])
            else
                results.μ[k][i] = min(penalty_max, penalty_scaling*results.μ[k][i])
            end
        else
            if abs(results.C[k][i]) <= constraint_decrease_ratio*abs(results.C_prev[k][i])
                results.μ[k][i] = min(penalty_max, penalty_scaling_no*results.μ[k][i])
            else
                results.μ[k][i] = min(penalty_max, penalty_scaling*results.μ[k][i])
            end
        end
    end

    return nothing
end

"""
$(SIGNATURES)
    Updates penalty (μ) and Lagrange multiplier (λ) parameters for Augmented Lagrangian method
"""
function outer_loop_update_type(results::ConstrainedIterResults,solver::Solver)::Nothing

    ## Lagrange multiplier updates
    solver.state.second_order_dual_update ? solve_batch_qp_dual(results,solver) : λ_update!(results,solver)

    ## Penalty updates
    μ_update!(results,solver)

    ## Store current constraints evaluations for next outer loop update
    results.C_prev .= deepcopy(results.C)

    return nothing
end

function outer_loop_update_type(results::UnconstrainedIterResults,solver::Solver)::Nothing
    return nothing
end
