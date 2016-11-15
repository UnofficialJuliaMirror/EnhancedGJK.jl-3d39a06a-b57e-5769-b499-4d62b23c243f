immutable Difference{PA, PB}
    a::PA
    b::PB
end

dot(n::Number, d::Difference) = Difference(dot(n, d.a), dot(n, d.b))
*(n::Number, d::Difference) = Difference(*(n, d.a), *(n, d.b))
dot(n::Number, t::Tagged) = n * value(t)
+(d1::Difference, d2::Difference) = Difference(d1.a + d2.a, d1.b + d2.b)

zero{PA, PB}(d::Difference{PA, PB}) = Difference(zero(d.a), zero(d.b))
# zero{PA, PB}(::Type{Difference{PA, PB}}) = Difference(zero(PA), zero(PB))


type CollisionCache{GeomA, GeomB, M, D1 <: Difference, D2 <: Difference}
    bodyA::GeomA
    bodyB::GeomB
    simplex_points::MVector{M, D1}
    closest_point::D2
end

function CollisionCache(geomA, geomB)
    N = dimension(typeof(geomA))
    @assert dimension(typeof(geomA)) == dimension(typeof(geomB))
    CollisionCache(N, geomA, geomB)
end

function edgespan(points::AbstractVector)
    span = [p - points[1] for p in points[2:end]]
end

function CollisionCache{N}(::Type{Val{N}}, geomA, geomB)
    simplex_points = [Difference(any_inside(geomA), any_inside(geomB))]
    closest_point = Difference(value(simplex_points[1].a), value(simplex_points[1].b))

    # Search for a starting simplex in the Minkowski difference by sampling
    # random directions until we find a set of points with linearly independent
    # edgespan.
    max_iter = 100
    for i in 1:max_iter
        direction = 2 * (rand(N) .- 0.5)
        candidate = Difference(support_vector_max(geomA, direction, simplex_points[1].a),
                               support_vector_max(geomB, -direction, simplex_points[1].b))
        mat = hcat(edgespan(map(p -> value(p.a) - value(p.b), [simplex_points..., candidate]))...)
        if det(mat' * mat) > 1e-3
            push!(simplex_points, candidate)
            if length(simplex_points) > N
                simplex = MVector{N+1}(simplex_points)
                return CollisionCache(geomA, geomB, simplex, closest_point)
            end
        end
    end

    error("Could not find a sensible initial simplex. Both geometries might have zero volume.")
end

dimension{G1, G2, M, D1, D2}(::Type{CollisionCache{G1, G2, M, D1, D2}}) = dimension(G1)

function argminmax(f::Function, iter)
    state = start(iter)
    min_arg, state = next(iter, state)
    max_arg = min_arg
    min_val = f(min_arg)
    max_val = min_val
    while !done(iter, state)
        arg, state = next(iter, state)
        val = f(arg)
        if val > max_val
            max_arg = arg
            max_val = val
        elseif val < min_val
            min_arg = arg
            min_val = val
        end
    end
    min_arg, max_arg
end

function support_vector_max(geometry, direction, initial_guess::Tagged)
    best_pt, score = gt.support_vector_max(geometry, direction)
    Tagged(convert(SVector, best_pt))
end

function support_vector_max{N, T}(pt::gt.Vec{N, T}, direction, initial_guess::Tagged)
    Tagged(convert(SVector, pt))
end


function support_vector_max{N, T}(mesh::gt.HomogenousMesh{gt.Point{N, T}}, direction, initial_guess::Tagged)
    best_arg, best_value = gt.argmax(x-> x⋅direction, gt.vertices(mesh))
    best_vec = convert(gt.Vec{N, T}, best_arg)
    Tagged(best_vec)
end

any_inside(pt::SVector) = Tagged(pt)
support_vector_max(pt::SVector, direction, initial_guess::Tagged) = Tagged(pt)

function gjk!(cache::CollisionCache, poseA::Transformation, poseB::Transformation)
    gjk!(dimension(cache.bodyA), cache, poseA, poseB)
end

function transform_simplex(cache::CollisionCache, poseA, poseB)
    transform_simplex(dimension(typeof(cache)), cache, poseA, poseB)
end

@generated function transform_simplex{N}(::Type{Val{N}}, cache::CollisionCache, poseA, poseB)
    transform_simplex_impl(N, cache, poseA, poseB)
end

function transform_simplex_impl(N, cache, poseA, poseB)
    Expr(:call, :(MVector),
        [:((poseA(value(cache.simplex_points[$i].a)) -
            poseB(value(cache.simplex_points[$i].b)))) for i in 1:(N + 1)]...)
end

function gjk!{N}(::Type{Val{N}}, cache::CollisionCache, poseA::Transformation, poseB::Transformation)
    const max_iter = 100
    const atol = 1e-6
    const origin = zeros(SVector{N, Float64})
    const rotAinv = transform_deriv(inv(poseA), origin)
    const rotBinv = transform_deriv(inv(poseB), origin)
    simplex = transform_simplex(cache, poseA, poseB)
    in_interior = false
    best_point = simplex[1]

    for k in 1:max_iter
        weights = projection_weights(simplex)
        min_weight, index_to_replace = findmin(weights)
        in_interior = min_weight > 0
        if in_interior
            break
        end
        best_point = dot(weights, simplex)
        @show best_point
        cache.closest_point = dot(weights, cache.simplex_points)

        direction = -best_point
        direction_in_A = rotAinv * direction
        direction_in_B = rotBinv * direction

        best_vertex_index, worst_vertex_index =
        argminmax(1:length(cache.simplex_points)) do i
            d = cache.simplex_points[i]
            dot(value(d.a), direction_in_A) + dot(value(d.b), -direction_in_B)
        end
        starting_vertex = cache.simplex_points[best_vertex_index]

        improved_vertex = Difference(
            support_vector_max(cache.bodyA, direction_in_A, starting_vertex.a),
            support_vector_max(cache.bodyB, -direction_in_B, starting_vertex.b))
        improved_point = poseA(value(improved_vertex.a)) - poseB(value(improved_vertex.b))
        score = dot(improved_point, direction)
        @show dot(best_point, direction)
        @show improved_point score
        if score <= dot(best_point, direction) + atol
            break
        else
            cache.simplex_points[index_to_replace] = improved_vertex
            simplex[index_to_replace] = improved_point
        end
    end
    return simplex, best_point, in_interior
end

function signed_distance!(cache::CollisionCache, poseA::Transformation, poseB::Transformation)
    signed_distance!(dimension(cache.bodyA), cache, poseA, poseB)
end

function signed_distance!{N}(dim::Type{Val{N}}, cache::CollisionCache, poseA::Transformation, poseB::Transformation)
    simplex, separation, in_collision = gjk!(dim, cache, poseA, poseB)

    if in_collision
        gt.with_immutable(simplex) do s
            const origin = zero(gt.Vec{N, Float64})
            _, penetration_distance = gt.argmax(1:length(s)) do i
                face = gt.simplex_face(s, i)
                weights, _ = projection_weights(origin, face)
                distance_to_face = norm(sum(face[i] * weights[i] for i in 1:length(face)))
                -distance_to_face
            end
            return penetration_distance
        end
    else
        return separation
    end
end
