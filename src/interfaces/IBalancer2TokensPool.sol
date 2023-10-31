// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

interface IBalancer2TokensPool {
    function getNormalizedWeights() external view returns (uint256[] memory);
}
