@testset "2d weights" begin
    simplex = SVector{3}(SVector{2, Float64}[[1., -1], [1., 1], [-1.5, 0]])
    weights = projection_weights(simplex)
    @test isapprox(weights, [0.3, 0.3, 0.4])
    @test isapprox(weights, projection_weights_reference(simplex))

    simplex = SVector{3}(SVector{2, Float64}[[1., -1], [1., 1], [1.5, 0]])
    weights = projection_weights(simplex)
    @test isapprox(weights, [0.5, 0.5, 0.0])
    @test isapprox(weights, projection_weights_reference(simplex))

    simplex = SVector{3}(SVector{2, Float64}[[1., -1], [1., 1], [0.5, 0]])
    weights = projection_weights(simplex)
    @test isapprox(weights, [0.0, 0.0, 1.0])
    @test isapprox(weights, projection_weights_reference(simplex))
end

@testset "3d weights" begin
    simplex = SVector{4}(SVector{3, Float64}[[1., -1, 0], [1., 1, 0], [0.4, 0, -0.1], [0.5, 0, 1]])
    weights = projection_weights(simplex)
    @test isapprox(weights, [0.0, 0.0,0.942623, 0.057377], atol=1e-6)
    @test isapprox(weights, projection_weights_reference(simplex))

    simplex = SVector{4}(SVector{3, Float64}[[1., -1, 0], [1., 1, 0], [1.4, 0, -0.1], [1.5, 0, 1]])
    weights = projection_weights(simplex)
    @test isapprox(weights, [0.5, 0.5, 0.0, 0.0])
    @test isapprox(weights, projection_weights_reference(simplex))
end

@testset "random simplex" begin
    Random.seed!(1)
    for i in 1:100
        simplex = SVector{4}([rand(SVector{3, Float64}) for i in 1:4])
        weights = projection_weights(simplex)
        @test all(weights .>= 0)
        @test isapprox(sum(weights), 1)
        @test isapprox(weights, projection_weights_reference(simplex))
    end
end

function test_no_penetration(simplex)
    weights = projection_weights(simplex)
    if all(x -> x > 0, weights)
        @show weights
        @test false
    end
end

@testset "numerical issues" begin
    # These simplices are degenerate in that all z-coordinates are the same.
    # Numerical issues due to floating point comparison can cause `projection_weights`
    # to return positive weights.
    let simplex = SVector{4, SVector{3, Float64}}([-3.33728783796428, 0.3321305518800686, 0.11004228580261734], [-3.33728783796428, -0.6678694481199314, 0.11004228580261734], [1.6627121620357201, -0.6678694481199314, 0.11004228580261734], [1.6627121620357201, 0.3321305518800686, 0.11004228580261734])
        test_no_penetration(simplex)
    end
    let simplex = SVector{4, SVector{3, Float64}}([-2.362029787803838, -0.4737843508044094, 0.11167470708499053], [2.637970212196162, 0.5262156491955906, 0.11167470708499053], [2.637970212196162, -0.4737843508044094, 0.11167470708499053], [-2.362029787803838, 0.5262156491955906, 0.11167470708499053])
        test_no_penetration(simplex)
    end
end
