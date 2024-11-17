import DynamicPPL: Model, VarInfo
import Random: Random, Xoshiro
import Test: @test, @testset
import ModelTests: ad_di, ad_ldp, MODELS, make_function, make_params
import DifferentiationInterfaceTest: test_differentiation, benchmark_differentiation, Scenario
using ADTypes

import ForwardDiff
import ReverseDiff
import Mooncake
import Zygote

"""
    ADTYPES::Vector{ADTypes.AbstractADType}

List of AD backends to test.
"""
ADTYPES = [
    AutoForwardDiff(),
    AutoReverseDiff(),
    AutoMooncake(; config=nothing),
    AutoZygote(),
]

"""
    REFERENCE_ADTYPE::ADTypes.AbstractADType

Reference AD backend to use for comparison. In this case, ForwardDiff.jl, since
it's the default AD backend used in Turing.jl.
"""
REFERENCE_ADTYPE = AutoForwardDiff()

"""
    get_adtype_shortname(adtype::ADTypes.AbstractADType)

Get the package name that corresponds to the the AD backend `adtype`. Only used
for pretty-printing.
"""
get_adtype_shortname(::AutoMooncake) = "Mooncake"
get_adtype_shortname(::AutoForwardDiff) = "ForwardDiff"
get_adtype_shortname(::AutoReverseDiff) = "ReverseDiff"
get_adtype_shortname(::AutoZygote) = "Zygote"

"""
    test_correctness(
        ad_function,
        model::Model,
        adtypes::Vector{<:ADTypes.AbstractADType},
        reference_adtype::ADTypes.AbstractADType,
        rng::Random.AbstractRNG=Xoshiro(468),
        params::Vector{<:Real}=VarInfo(rng, model)[:];
        value_atol=1e-6,
        grad_atol=1e-6
    )

Test the correctness of all the AD backend `adtypes` for the model `model`
using the implementation `ad_function`. The test is performed by calculating
the logdensity and its gradient using all the AD backends, and comparing the
results against that obtained with the reference AD backend `reference_adtype`.

The parameters can either be passed explicitly using the `params` argument, or can
be sampled from the prior distribution of the model using the `rng` argument.
"""
function test_correctness(
    ad_function,
    model::Model,
    adtypes::Vector{<:ADTypes.AbstractADType},
    reference_adtype::ADTypes.AbstractADType,
    rng::Random.AbstractRNG=Xoshiro(468),
    params::Vector{<:Real}=VarInfo(rng, model)[:];
    value_atol=1e-6,
    grad_atol=1e-6
)
    value_true, grad_true = ad_function(model, reference_adtype, params)
    for adtype in adtypes
        value, grad = ad_function(model, adtype, params)
        info_str = join([
            "Testing correctness",
            " AD function : $(ad_function)",
            "     backend : $(get_adtype_shortname(adtype))",
            "       model : $(model.f)",
            "      params : $(params)",
            "      actual : $((value, grad))",
            "    expected : $((value_true, grad_true))",
        ], "\n")
        @info info_str
        @test value ≈ value_true atol=value_atol
        @test grad ≈ grad_true atol=grad_atol
    end
end

# Can test the ad_ldp and ad_di functions to ensure coverage of Turing code
@testset "$(model.f)" for model in MODELS
    test_correctness(ad_ldp, model, ADTYPES, REFERENCE_ADTYPE)
    test_correctness(ad_di, model, ADTYPES, REFERENCE_ADTYPE)
end

# Alternatively, we can test these manually with DifferentiationInterfaceTest,
# and even benchmark them. This is really neat but doesn't reflect the actual
# code used in Turing.
scenarios = map(MODELS) do model
    f = make_function(model)
    x = make_params(model)
    true_grad = ad_ldp(model, REFERENCE_ADTYPE, x)[2]
    Scenario{:gradient, :out}(f, x; res1=true_grad)
end
test_differentiation(ADTYPES, scenarios)
benchmark_differentiation(ADTYPES, scenarios)
