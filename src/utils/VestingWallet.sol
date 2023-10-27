// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {VestingWalletUpgradeable as OzVestingWallet} from "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";

contract VestingWallet is OzVestingWallet {
    function initialize(address beneficiary, uint64 durationSecs) initializer public {
        __VestingWallet_init(beneficiary, uint64(block.timestamp), durationSecs);
    }
}
