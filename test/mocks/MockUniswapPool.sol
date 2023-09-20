// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {IBalancerTwapOracle} from "../../src/interfaces/IBalancerTwapOracle.sol";
import {IUniswapTwapOracle} from "../../src/interfaces/IUniswapTwapOracle.sol";

contract MockUniswapPool is IUniswapTwapOracle {
    int56[2] cumulatives;

    function setCumulatives(int56[2] memory value) external {
        cumulatives = value;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        secondsAgos;
        secondsPerLiquidityCumulativeX128s;

        tickCumulatives = new int56[](2);
        tickCumulatives[0] = cumulatives[0];
        tickCumulatives[1] = cumulatives[1];
    }
}
