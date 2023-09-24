// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IOracle} from "./interfaces/IOracle.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";

/// @title Options Token
/// @notice Options token representing the right to perform an advantageous action,
/// such as purchasing the underlying token at a discount to the market price.
contract OptionsToken is ERC20, Owned, IERC20Mintable {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error OptionsToken__NotTokenAdmin();

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The contract that has the right to mint options tokens
    address public immutable tokenAdmin;

    /// @notice The underlying token purchased during redemption
    IERC20Mintable public immutable underlyingToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address tokenAdmin_,
        IERC20Mintable underlyingToken_
    ) ERC20(name_, symbol_, 18) Owned(owner_) {
        tokenAdmin = tokenAdmin_;
        underlyingToken = underlyingToken_;
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Called by the token admin to mint options tokens
    /// @param to The address that will receive the minted options tokens
    /// @param amount The amount of options tokens that will be minted
    function mint(address to, uint256 amount) external virtual override {
        /// -----------------------------------------------------------------------
        /// Verification
        /// -----------------------------------------------------------------------

        if (msg.sender != tokenAdmin) revert OptionsToken__NotTokenAdmin();

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // skip if amount is zero
        if (amount == 0) return;

        // mint options tokens
        _mint(to, amount);
    }
}
