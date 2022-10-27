@testset "Bond" begin

  # check BondOrderTypes first
  @test BondOrderType(1) == BondOrder.Single
  @test BondOrderType(2) == BondOrder.Double
  @test BondOrderType(3) == BondOrder.Triple
  @test BondOrderType(4) == BondOrder.Quadruple
  @test BondOrderType(100) == BondOrder.Unknown
  @test_throws ArgumentError BondOrderType(5)
  @test_throws ArgumentError BondOrderType(-1)

  # create a simple bond
  b0 = (a1 = 1, 
        a2 = 3, 
        order = BondOrder.Single)
  
  @test b0 isa Bond
  @test b0.a1 == 1
  @test b0.a2 == 3
  @test b0.order == BondOrder.Single
 
  # create nonsense bond
  b1 = ( a1 = 1,
         a2 = "bla",
         order = BondOrderType(2)
      )
  
  @test !isa(b1, Bond)

  # create other bonds
  for i in [3, 4, 100]
    b3 = ( a1 = 1,
          a2 = 2,
          order = BondOrderType(i)
        )
    @test b3 isa Bond
    @test b3.a1 == 1
    @test b3.a2 == 2
    if i == 3
      @test b3.order == BondOrder.Triple
    elseif i == 4
      @test b3.order == BondOrder.Quadruple
    else
      @test b3.order == BondOrder.Unknown
    end
  end
end
