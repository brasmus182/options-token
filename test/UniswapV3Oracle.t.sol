// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {UniswapV3Oracle} from "../src/oracles/UniswapV3Oracle.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapPool} from "../src/interfaces/IUniswapPool.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Params {
    MockUniswapPool source;
    address token;
    address owner;
    uint16 multiplier;
    uint32 secs;
    uint32 ago;
    uint128 minPrice;
}

contract UniswapOracleTest is Test {
    using stdStorage for StdStorage;

    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    address WETH_OP_POOL_ADDRESS = 0x68F5C0A2DE713a54991E01858Fd27a3832401849;
    address OP_ADDRESS = 0x4200000000000000000000000000000000000042;

    MockUniswapPool mockV3Pool;

    // observation on 2023-09-20 11:26 UTC-3, UNIWETH Ethereum Pool
    int56[2] sampleCumulatives = [int56(-4072715107990), int56(-4072608557758)];

    // expected price in terms of token0
    uint256 expectedPriceToken0 = 372078200928347021722;

    Params _default;
    uint256 opFork;

    function setUp() public {
        mockV3Pool = new MockUniswapPool();
        mockV3Pool.setCumulatives(sampleCumulatives);
        mockV3Pool.setToken0(OP_ADDRESS);
        _default = Params(mockV3Pool, OP_ADDRESS, address(this), 10000, 30 minutes, 0, 1000);
        opFork = vm.createFork(OPTIMISM_RPC_URL);
    }

    /// Mock tests

    function test_PriceToken0() public {
        UniswapV3Oracle oracle = new UniswapV3Oracle(
            _default.source,
            OP_ADDRESS,
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
        UniswapV3Oracle oracle = new UniswapV3Oracle(
            _default.source,
            address(0),
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
            _default.token,
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

    /// On-chain tests

    function test_PriceOpPool() internal {
        vm.selectFork(opFork);

        address manipulator1 = makeAddr("manipulator1");
        address manipulator2 = makeAddr("manipulator2");

        abi.decode(abi.encode(vm.load(OP_ADDRESS, bytes32(0))), (bytes32));

        bytes32 balanceSlot = keccak256(abi.encode(manipulator1, 0));
        vm.store(OP_ADDRESS, balanceSlot, bytes32(uint256(1 ether)));

        // increase OP balance of manipulator1
        stdstore.target(OP_ADDRESS).sig("_balances(address)").with_key(manipulator1).checked_write(1 ether);

        UniswapV3Oracle oracle = new UniswapV3Oracle(
            IUniswapPool(WETH_OP_POOL_ADDRESS),
            OP_ADDRESS,
            _default.owner,
            _default.multiplier,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 price1 = oracle.getPrice();
    }
}
