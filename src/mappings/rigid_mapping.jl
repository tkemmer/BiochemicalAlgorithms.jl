using Statistics: mean
using LinearAlgebra: Hermitian, eigen

export 
    AbstractRMSDMinimizer, 
    RigidTransform, 
    rigid_transform!, 
    compute_rmsd_minimizer, 
    compute_rmsd, 
    translate!, 
    map_rigid!,
    match_points

abstract type AbstractRMSDMinimizer end
abstract type RMSDMinimizerKabsch <: AbstractRMSDMinimizer end

struct RigidTransform{T<:Real}
    rotation::Matrix3{T}
    translation::Vector3{T}

    function RigidTransform{T}(r::Matrix3{T}, t::Vector3{T}) where {T<:Real}
        new(r, t)
    end
end

RigidTransform(r::Matrix3, t::Vector3) = RigidTransform{Float32}(r, t)


### Functions

function translate!(m::AbstractMolecule{T}, t::Vector3{T}) where {T<:Real}
    DataFramesMeta.@with atoms_df(m) begin
       :r .= Ref(t) .+ :r
    end
    m
end

function rigid_transform!(m::AbstractMolecule{T}, transform::RigidTransform{T}) where {T<:Real}
    DataFramesMeta.@with atoms_df(m) begin
        :r .= Ref(transform.rotation) .* :r .+ Ref(transform.translation)
    end
    m
end

function compute_rmsd(f::AbstractAtomBijection{T}) where {T<:Real}
    r_BA = Vector{Vector3{T}}(undef, size(f.atoms_A, 1))
    DataFramesMeta.@with f.atoms_A r_BA .= :r
    DataFramesMeta.@with f.atoms_B r_BA .-= :r
    sqrt(mean(map(r -> transpose(r) * r, r_BA)))
end

function compute_rmsd_minimizer(f::AbstractAtomBijection{T}) where {T<:Real}
    r_A = Vector{Vector3{T}}(undef, size(f.atoms_A, 1))
    DataFramesMeta.@with f.atoms_A r_A .= :r
    mean_A = mean(r_A)

    r_B = Vector{Vector3{T}}(undef, size(f.atoms_B, 1))
    DataFramesMeta.@with f.atoms_B r_B .= :r
    mean_B = mean(r_B)

    R = mapreduce(t -> t[1] * transpose(t[2]), +, zip(r_B .- Ref(mean_B), r_A .- Ref(mean_A)))

    C = Hermitian(transpose(R) * R)
    μ, a = eigen(C)

    RigidTransform{T}(mapreduce(i -> 1/√μ[i] * (R * a[:, i]) * transpose(a[:, i]), +, 1:3), mean_B - mean_A)
end

compute_rmsd_minimizer(f) = compute_rmsd_minimizer{Float32}(f)

function map_rigid!(A::AbstractMolecule{T}, B::AbstractMolecule{T}; heavy_atoms_only::Bool = false) where {T<:Real}
    atoms_A = atoms_df(A)
    heavy_atoms_only && (atoms_A = atoms_A[atoms_A.element .!== Elements.H, :])

    U = compute_rmsd_minimizer(TrivialAtomBijection(atoms_A, B))

    rigid_transform!(A, U)

    A
end

# The transformation maps 
# (1) the point(vector3) w1 onto the point v1 and  
# (2) the point w2 onto the ray that starts in v1 and goes through v2
# (3) the point w3 into the plane generated by v1, v2 and v3
function match_points(
        w1::Vector3{T}, w2::Vector3{T}, w3::Vector3{T},
        v1::Vector3{T}, v2::Vector3{T}, v3::Vector3{T}) where {T<:Real}
    ϵ = T(0.00001)
    ϵ₂ = T(0.00000001)

    # Compute the translations that map v1 and w1 onto the origin 
    # and apply them to v2, v3 and w2, w3.
    tw2 = w2 - w1
    tw3 = w3 - w1

    tv2 = v2 - v1
    tv3 = v3 - v1

    dist_v2_v1 = squared_norm(tv2)
    dist_w2_w1 = squared_norm(tw2)
    dist_w3_w1 = squared_norm(tw3)
    dist_v3_v1 = squared_norm(tv3)

    # Try to remove nasty singularities arising if the first two
    # points in each point set are too close to each other:
    #   (a) ensure (v2 != v1) 
    if ((dist_v2_v1 < ϵ₂) && (dist_v3_v1 >= ϵ₂))
        tv3, tv2 = tv2, tv3
    end

    #   (b) ensure (w2 != w1) 
    if ((dist_w2_w1 < ϵ₂) && (dist_w3_w1 >= ϵ₂))
        tw3, tw2 = tw2, tw3
    end

    # initialize translation
    final_translation = -w1
    final_rotation = T(1)I(3)

    if ((squared_norm(tv2) >= ϵ₂) && (squared_norm(tw2) >= ϵ₂))
        # calculate the rotation axis: orthogonal to tv2 and tw2
        tw2 = normalize(tw2)
        tv2 = normalize(tv2)

        rotation_axis = tw2 + tv2

        rotation = if (squared_norm(rotation_axis) < ϵ)
            # the two axes seem to be antiparallel -
            # invert the second vector
            T(-1)I(3)
        else
            # rotate around the rotation axis
            AngleAxis{T}(π, rotation_axis...)
        end

        tw2 = rotation * tw2
        tw3 = rotation * tw3

        final_rotation    = rotation * final_rotation
        final_translation = rotation * final_translation

        if ((squared_norm(tw3) > ϵ₂) && (squared_norm(tv3) > ϵ₂))
            tw3 = normalize(tw3)
            tv3 = normalize(tv3)

            axis_w = cross(tv2, tw3)
            axis_v = cross(tv2, tv3)

            if ((squared_norm(axis_v) > ϵ₂) && (squared_norm(axis_w) > ϵ₂))
                axis_v = normalize(axis_v)
                axis_w = normalize(axis_w)

                rotation_axis = cross(axis_w, axis_v)

                if (squared_norm(rotation_axis) < ϵ₂)
                    scalar_prod = dot(axis_w, axis_v)
                    rotation = if (scalar_prod < 0.0)
                        AngleAxis{T}(π, tv2...)
                    else
                        T(1)I(3)
                    end
                else
                    # Compute the rotation that maps tw3 onto tv3
                    product = dot(axis_w, axis_v)
                    product = min(T(1.0), max(T(-1.0), product))

                    angle = acos(product)
                    rotation = if (angle > ϵ)
                        AngleAxis{T}(angle, rotation_axis...)
                    else
                        # Use the identity matrix instead.
                        T(1.0)I(3)
                    end
                end

                final_rotation    = rotation * final_rotation
                final_translation = rotation * final_translation
            end
        end
    end

    # apply the translation onto v1
    final_translation += v1

    # done
    return final_translation, final_rotation
end
