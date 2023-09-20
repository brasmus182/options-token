// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {UniswapV3Oracle} from "../src/oracles/UniswapV3Oracle.sol";
import {IUniswapTwapOracle} from "../src/interfaces/IUniswapTwapOracle.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

struct Params {
    IUniswapTwapOracle source;
    bool isToken0;
    address owner;
    uint16 multiplier;
    uint32 secs;
    uint32 ago;
    uint128 minPrice;
}

contract UniswapOracleTest is Test {
    MockUniswapPool mockV3Pool;

    int56[2] sampleCumulatives = [int56(-4072715107990), int56(-4072608557758)];
    // observation on 2023-09-20 11:26 UTC-3, UNIWETH Ethereum Pool

    // expected price in terms of token0
    uint256 expectedPriceToken0 = 372078200928347021722;

    Params _default;

    function setUp() public {
        mockV3Pool = new MockUniswapPool();
        mockV3Pool.setCumulatives(sampleCumulatives);
        _default = Params(mockV3Pool, true, address(this), 10000, 30 minutes, 0, 1000);
    }

    function test_PriceToken0() public {
        bool isToken0 = true;
        UniswapV3Oracle oracle = new UniswapV3Oracle(
            _default.source,
            isToken0,
            _default.owner,
            _default.multiplier,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 price = oracle.getPrice();
        assertEq(price, expectedPriceToken0);
    }

    function test_PriceToken1() public {
        bool isToken0 = false;
        UniswapV3Oracle oracle = new UniswapV3Oracle(
            _default.source,
            isToken0,
            _default.owner,
            _default.multiplier,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 price = oracle.getPrice();
        uint256 expectedPriceToken1 = price = FixedPointMathLib.divWadUp(1e18, price);
        assertEq(price, expectedPriceToken1);
    }

    function test_PriceToken0Multiplier() public {
        uint16 multiplier = 5000;
        UniswapV3Oracle oracle = new UniswapV3Oracle(
            _default.source,
            _default.isToken0,
            _default.owner,
            multiplier,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 price = oracle.getPrice();
        uint256 expectedPriceWithMultiplier = FixedPointMathLib.mulDivUp(expectedPriceToken0, multiplier, 10000);
        assertEq(price, expectedPriceWithMultiplier);
    }
}
