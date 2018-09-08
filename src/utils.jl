function println(level::Symbol, msg::String)::Void
    if level_priorities[level] ≥ level_priorities[debug_level::Symbol]
        println(msg)
    end
end

print_info(msg) = println(:info,msg)
print_debug(msg) = println(:debug,msg)

#TODO finish
function plot_cost(results::ResultsCache)
    index_outerloop = find(x -> x == 1, results.iter_type)
end

"""
@(SIGNATURES)

Generate an animation of a trajectory as it evolves during a solve
"""
function trajectory_animation(results::ResultsCache;traj::String="state",ylim=[-10;10],title::String="Trajectory Evolution",filename::String="trajectory.gif",fps::Int=1)::Void
    anim = @animate for i=1:results.termination_index
        if traj == "state"
            t = results.result[i].X'
        elseif traj == "control"
            t = results.result[i].U'
        end
        plot(t,ylim=(ylim[1],ylim[2]),size=(200,200),label="",width=1,title=title)
        if results.iter_type[i] == 2
            plot!(xlabel="Infeasible->Feasible") # note the transition from an infeasible to feasible solve
        end
    end

    path = joinpath(Pkg.dir("TrajectoryOptimization"),filename)
    gif(anim,path,fps=fps)
    return nothing
end

"""
@(SIGNATURES)

Generate an animation of a pendulum
"""
function pendulum_animation(results::SolverResults;filename::String="pendulum.gif",fps::Int=1)::Void
    anim = @animate for i=1:size(results1.X,2)
        x = cos(results1.X[1,i] - pi/2)
        y = sin(results1.X[1,i] - pi/2)
        plot([0,x],[0,y],xlims=(-1.5,1.5),ylims=(-1.5,1.5),color="black",size=(300,300),label="",title="Pendulum")
    end
    path = joinpath(Pkg.dir("TrajectoryOptimization"),filename)
    gif(anim,path,fps=fps)
    return nothing
end

"""
@(SIGNATURES)

    Convert ZYX Euler angles to quaternion [s;v]
"""
function eul2quat(eul)
    ## Translate the given Euler angle with a specified axis rotation sequence into the corresponding quaternion:

    quat = zeros(4,1)
    # case 'ZYX'
	c_1 = cos(eul[1,1]*0.5)
	s_1 = sin(eul[1,1]*0.5)
	c_2 = cos(eul[2,1]*0.5)
	s_2 = sin(eul[2,1]*0.5)
	c_3 = cos(eul[3,1]*0.5)
	s_3 = sin(eul[3,1]*0.5)

    # https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19770024290.pdf, the original algorithm has q = [s;v]
	quat[4,1] = c_1*c_2*c_3 + s_1*s_2*s_3
	quat[1,1] = c_1*c_2*s_3 - s_1*s_2*c_3
	quat[2,1] = c_1*s_2*c_3 + s_1*c_2*s_3
	quat[3,1] = s_1*c_2*c_3 - c_1*s_2*s_3

    quat
end

"""
@(SIGNATURES)

    Convert rotation matrix to Euler angles (ZYX)
"""
function rot2eul(R)
    [atan(R[2,1]/R[1,1]);
     atan(-R[3,1]/sqrt(1 - R[3,1]^2));
     atan(R[3,2]/R[3,3])]
end

"""
@(SIGNATURES)

    Convert quaternion (q = [s;v]) rotation matrix
"""
function quat2rot(q)
    q1 = q[4]; q2 = q[1]; q3 = q[2]; q4 = q[3]
    M = zeros(3,3)

    M = [(q1^2 + q2^2 - q3^2 - q4^2) 2*(q2*q3 - q1*q4) 2.*(q2*q4 + q1*q3);
         2.*(q2*q3 + q1*q4) (q1^2 - q2^2 + q3^2 - q4^2) 2.*(q3*q4 - q1*q2);
         2.*(q2*q4 - q1*q3) 2*(q3*q4 + q1*q2) (q1^2 - q2^2 - q3^2 + q4^2)]
end

"""
@(SIGNATURES)

Plot a 3D trajectory (static)
"""
function plot_3D_trajectory(results::ResultsCache, solver::Solver;xlim=[-10.0;10.0],ylim=[-10.0;10.0],zlim=[-10.0;10.0],title::String="3D Trajectory")::Void
    # initialize a 3D plot with 1 empty series
    plt = path3d(1, xlim=(xlim[1],xlim[2]), ylim=(ylim[1],ylim[2]), zlim=(zlim[1],zlim[2]),
                    xlab = "", ylab = "", zlab = "",
                    title=title,legend=nothing,color="blue",width=2)

    # build 3D plot
    for i=1:solver.N
        push!(plt, results.X[1,i], results.X[2,i], results.X[3,i])
    end
    plot!((solver.obj.x0[1],solver.obj.x0[2],solver.obj.x0[3]),marker=(:circle,"red"))
    plot!((solver.obj.xf[1],solver.obj.xf[2],solver.obj.xf[3]),marker=(:circle,"green"))
    display(plt)
    return nothing
end

function linear_spline(x1::Array,x2::Array,T::Float64)
    x = zeros(x1)
    f(t) = begin
        for i in eachindex(M1)
            x[i] = (x2[i] - x1[i])/T*t + x1[i]
        end
        x
    end
end

function quadratic_spline(xdot::Array,x1::Array,x2::Array,T::Float64)
    f(t) = begin
        0.5*(2*x2/T^2 - 2*x1/T^2 - 2*xdot/T)*t^2 + xdot*t + x1
    end
end

function print_solver(solver::Solver,name::String,io::IO=STDOUT)
    println(io,"###  $name  ###")

    println(io,"\nModel Props")
    println(io,"-----------")
    println(io,"\t n: $(solver.model.n)")
    println(io,"\t m: $(solver.model.m)")
    println(io,"\t inplace dynamics?: $(is_inplace_dynamics(solver.model))")

    println(io,"\nObjective")
    println(io,"----------")
    println(io,"\t tf: $(obj.tf)")
    println(io,"\t x0: $(obj.x0)")
    println(io,"\t xf: $(obj.xf)")
    println(io,"\t Q: $(diag(obj.Q))")
    println(io,"\t R: $(diag(obj.R))")

    println(io,"\nSolver Settings")
    println(io,"-----------------")
    println(io,"\t dt: $(solver.dt)")
    println(io,"\t N: $(solver.N)")
    println(io,"\t integration: $(solver.integration)")

end

"""
$(SIGNATURES)
Checks if Snopt.jl is installed and the SNOPT library has been built.
Does not check if Snopt.jl runs, only that the necessary files are there.
NOTE: Snopt.jl does not currently support Windows.
"""
function check_snopt_installation()::Bool
    if is_windows()
        return false
    end
    snopt_dir = Pkg.dir("Snopt")
    if isdir(snopt_dir)
        if isfile(joinpath(snopt_dir),"deps","src","libsnopt.so")
            return true
        end
    end
    return false
end

"""
$(SIGNATURES)
Circle constraint function (c ⩽ 0, negative is satisfying constraint)
"""
function circle_constraint(x,x0,y0,r)
	return -((x[1]-x0)^2 + (x[2]-y0)^2  - r^2)
end

"""
$(SIGNATURES)
Sphere constraint function (c ⩽ 0, negative is satisfying constraint)
"""
function sphere_constraint(x,x0,y0,z0,r)
	return -((x[1]-x0)^2 + (x[2]-y0)^2 + (x[3]-z0)^2  - r^2)
end

"""
$(SIGNATURES)
Generate random circle constraints
"""
function generate_random_circle_obstacle_field(n_circles::Int64,x_rand::Float64=10.0,y_rand::Float64=10.0,r_rand::Float64=0.5)
    x0 = x_rand*rand(n_circles)
    y0 = y_rand*rand(n_circles)
    r = r_rand*ones(n_circles)

    function constraints(x,u)::Array
        c = zeros(typeof(x[1]),n_circles)

        for i = 1:n_circles
            c[i] = circle_constraint(x,x0[i],y0[i],r[i])
        end
        c
    end
    constraints, (x0, y0, r)
end

"""
$(SIGNATURES)
Generate random sphere constraints
"""
function generate_random_sphere_obstacle_field(n_spheres::Int64,x_rand::Float64=10.0,y_rand::Float64=10.0,z_rand::Float64=10.0,r_rand::Float64=0.5)
    x0 = x_rand*rand(n_sphere)
    y0 = y_rand*rand(n_spheres)
    z0 = z_rand*rand(n_spheres)
    r = r_rand*ones(n_spheres)

    function constraints(x,u)::Array
        c = zeros(typeof(x[1]),n_spheres)

        for i = 1:n_spheres
            c[i] = sphere_constraint(x,x0[i],y0[i],z0[i],r[i])
        end
        c
    end
    constraints, (x0, y0, z0, r)
end
