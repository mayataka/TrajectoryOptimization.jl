include("quaternions.jl")

struct Quadrotor{T} <: AbstractModel #RigidBody{Quat{VectorPart}}
      n::Int
      m::Int
      mass::T
      J::SMatrix{3,3,T,9}
      Jinv::SMatrix{3,3,T,9}
      gravity::SVector{3,T}
      motor_dist::T
      kf::T
      km::T
      info::Dict{Symbol,Any}
end

function Quadrotor(;mass=0.5,
                   J=SMatrix{3,3}(Diagonal([0.0023, 0.0023, 0.004])),
                   gravity=SVector(0,0,-9.81),
                   motor_dist=0.1750,
                   kf=1.0,
                   km=0.0245,
                   info=Dict{Symbol,Any}())

    Quadrotor(13,4,mass,J,inv(J),gravity,motor_dist,kf,km,info)
end

function dynamics(quad::Quadrotor, x::AbstractVector, u::AbstractVector)
      # Quaternion representation
      # Modified from D. Mellinger, N. Michael, and V. Kumar,
      # "Trajectory generation and control for precise aggressive maneuvers with quadrotors",
      # In Proceedings of the 12th International Symposium on Experimental Robotics (ISER 2010), 2010.

      ## States: X ∈ R^13; q = [s;v]
      # x
      # y
      # z
      # q0
      # q1
      # q2
      # q3
      # xdot
      # ydot
      # zdot
      # omega1
      # omega2
      # omega3

      # x = X[1:3]
      q = normalize(Quaternion(view(x,4:7)))
      # q = view(x,4:7)
      # normalize!(q)
      v = view(x,8:10)
      omega = x[@SVector [11,12,13]]

      # Parameters
      m = quad.mass # mass
      J = quad.J # inertia matrix
      Jinv = quad.Jinv # inverted inertia matrix
      g = quad.gravity # gravity
      L = quad.motor_dist # distance between motors
      kf = quad.kf # 6.11*10^-8;
      km = quad.km

      w1 = u[1]
      w2 = u[2]
      w3 = u[3]
      w4 = u[4]

      F1 = kf*w1;
      F2 = kf*w2;
      F3 = kf*w3;
      F4 = kf*w4;
      F = @SVector [0., 0., F1+F2+F3+F4] #total rotor force in body frame

      M1 = km*w1;
      M2 = km*w2;
      M3 = km*w3;
      M4 = km*w4;
      tau = @SVector [L*(F2-F4), L*(F3-F1), (M1-M2+M3-M4)] #total rotor torque in body frame

      # ẋ[4:7] = 0.5*qmult(q,[0;omega]) #quaternion derivative
      qdot = SVector(0.5*q*Quaternion(zero(x[1]), omega))
      vdot = g + (1/m)*(q*F) #acceleration in world frame
      omdot = Jinv*(tau - cross(omega,J*omega)) #Euler's equation: I*ω + ω x I*ω = constraint_decrease_ratio
      @SVector [v[1], v[2], v[3], qdot[1], qdot[2], qdot[3], qdot[4], vdot[1], vdot[2], vdot[3], omdot[1], omdot[2], omdot[3]]
end


function state_diff(quad::Quadrotor, x, x0)
      inds = @SVector [4,5,6,7]
      q = x[inds]
      q0 = x0[inds]
      δx = x - x0
      δq = quat_diff(q, q0)
      δx = @SVector [δx[1], δx[2], δx[3], δq[1], δq[2], δq[3], δx[8], δx[9], δx[10], δx[11], δx[12], δx[13]]
end

function quat_diff(q2::SVector{4,T1}, q1::SVector{4,T2}) where {T1,T2}
    # equivalent to q2 - q1
    # same as inv(q1)*q2
    vec = @SVector [2,3,4]
    s1,v1 = q1[1],-q1[vec]
    s2,v2 = q2[1], q2[vec]  # needs an inverse
    # this is q1*q2
    s1*v2 + s2*v1 + v1 × v2
end

function quat_diff_jacobian(q::SVector{4,T}) where T
    w,x,y,z = q
    x,y,z = -x,-y,-z  # invert q
    @SMatrix [x  w -z  y;
              y  z  w -x;
              z -y  x  w];
end

function state_diff_jacobian(quad::Quadrotor, x0::SVector{N,T}) where {N,T}
      inds = @SVector [4,5,6,7]
      q0 = x0[inds]
      G = quat_diff_jacobian(q0)
      I1 = @SMatrix [1 0 0 0 0 0 0 0 0 0 0 0 0;
                     0 1 0 0 0 0 0 0 0 0 0 0 0;
                     0 0 1 0 0 0 0 0 0 0 0 0 0;
                     0 0 0 G[1] G[4] G[7] G[10] 0 0 0 0 0 0;
                     0 0 0 G[2] G[5] G[8] G[11] 0 0 0 0 0 0;
                     0 0 0 G[3] G[6] G[9] G[12] 0 0 0 0 0 0;
                     0 0 0 0 0 0 0 1 0 0 0 0 0;
                     0 0 0 0 0 0 0 0 1 0 0 0 0;
                     0 0 0 0 0 0 0 0 0 1 0 0 0;
                     0 0 0 0 0 0 0 0 0 0 1 0 0;
                     0 0 0 0 0 0 0 0 0 0 0 1 0;
                     0 0 0 0 0 0 0 0 0 0 0 0 1.]
end

@inline state_diff_size(::Quadrotor) = 12


struct Quadrotor2{T,R} <: RigidBody{R}
      n::Int
      m::Int
      mass::T
      J::Diagonal{T,SVector{3,T}}
      Jinv::Diagonal{T,SVector{3,T}}
      gravity::SVector{3,T}
      motor_dist::T
      kf::T
      km::T
      info::Dict{Symbol,Any}
end

function Quadrotor2{R}(;mass=0.5,
                   J=Diagonal(@SVector [0.0023, 0.0023, 0.004]),
                   gravity=SVector(0,0,-9.81),
                   motor_dist=0.1750,
                   kf=1.0,
                   km=0.0245,
                   info=Dict{Symbol,Any}()) where R
    Quadrotor2{Float64,R}(13,4,mass,J,inv(J),gravity,motor_dist,kf,km,info)
end


function forces(model::Quadrotor2, x, u)
      q = normalize(Quaternion(x[4],x[5],x[6],x[7]))
      kf = model.kf
      g = model.gravity
      m = model.mass

      w1 = u[1]
      w2 = u[2]
      w3 = u[3]
      w4 = u[4]

      F1 = kf*w1;
      F2 = kf*w2;
      F3 = kf*w3;
      F4 = kf*w4;
      F = @SVector [0., 0., F1+F2+F3+F4] #total rotor force in body frame

      m*g + q*F #acceleration in world frame
end

function moments(model::Quadrotor2, x, u)
      kf, km = model.kf, model.km
      L = model.motor_dist

      w1 = u[1]
      w2 = u[2]
      w3 = u[3]
      w4 = u[4]

      F1 = kf*w1;
      F2 = kf*w2;
      F3 = kf*w3;
      F4 = kf*w4;

      M1 = km*w1;
      M2 = km*w2;
      M3 = km*w3;
      M4 = km*w4;
      tau = @SVector [L*(F2-F4), L*(F3-F1), (M1-M2+M3-M4)] #total rotor torque in body frame
end

inertia(model::Quadrotor2, x, u) = model.J
inertia_inv(model::Quadrotor2, x, u) = model.Jinv
mass_matrix(model::Quadrotor2, x, u) = Diagonal(@SVector fill(model.mass,3))
