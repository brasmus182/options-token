// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IVault as BalancerPool} from "balancer-interfaces/vault/IVault.sol";
import {IAsset} from "balancer-interfaces/vault/IAsset.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {OptionsToken} from "../OptionsToken.sol";

/// @title Options Token Exercise Contract
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract Exercise is Owned {
    /// Library usage
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// Errors
    error Exercise__PastDeadline();
    error Exercise__NotTokenAdmin();
    error Exercise__SlippageTooHigh();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);

    /// Immutable parameters
    ERC20 public immutable paymentToken;
    IERC20Mintable public immutable underlyingToken;
    OptionsToken public immutable oToken;

    /// Storage variables
    IOracle public oracle;
    address public treasury;
    address public balVault;
    address public otherTokenAddress;
    address public ethTokenAddress;

    // New state variable for Balancer's PoolId
    bytes32 public balancerPoolId;

    constructor(
        OptionsToken oToken_,
        address owner_,
        ERC20 paymentToken_,
        IERC20Mintable underlyingToken_,
        IOracle oracle_,
        address treasury_
    ) Owned(owner_) {
        oToken = oToken_;
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;
        oracle = oracle_;
        treasury = treasury_;

        emit SetOracle(oracle_);
        emit SetTreasury(treasury_);
    }

    /// External functions
    function exercise(uint256 amount, uint256 maxPaymentAmount, address recipient)
        external
        virtual
        returns (uint256 paymentAmount)
    {
        return _exercise(amount, maxPaymentAmount, recipient);
    }

    function exercise(uint256 amount, uint256 maxPaymentAmount, address recipient, uint256 deadline)
        external
        virtual
        returns (uint256 paymentAmount)
    {
        if (block.timestamp > deadline) revert Exercise__PastDeadline();
        return _exercise(amount, maxPaymentAmount, recipient);
    }

    /// Owner functions
    function setOracle(IOracle oracle_) external onlyOwner {
        oracle = oracle_;
        emit SetOracle(oracle_);
    }

    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
        emit SetTreasury(treasury_);
    }

    // New function to set Balancer's Pool ID
    function setBalancerPoolId(bytes32 _poolId) external onlyOwner {
        balancerPoolId = _poolId;
    }

    /// The function to Zap into the 80%/20% Token/ETH pool in Balancer
    function zapIntoBalancerPool(uint256 ethAmount, uint256 tokenAmount, uint256 minBPTOut) external {
        require(balancerPoolId != bytes32(0), "Balancer Pool ID not set");

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = ethAmount;
        amountsIn[1] = tokenAmount;

        bytes memory userData = abi.encode(uint8(1), amountsIn, minBPTOut); // uint8(1) represents JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(ethTokenAddress);
        assets[1] = IAsset(otherTokenAddress);

        BalancerPool.JoinPoolRequest memory request = BalancerPool.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        ERC20(ethTokenAddress).safeTransferFrom(msg.sender, address(this), ethAmount);
        ERC20(otherTokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Ensure enough allowance for both tokens
        if (ERC20(ethTokenAddress).allowance(address(this), balVault) < ethAmount) {
            ERC20(ethTokenAddress).approve(balVault, ethAmount);
        }
        if (ERC20(otherTokenAddress).allowance(address(this), balVault) < tokenAmount) {
            ERC20(otherTokenAddress).approve(balVault, tokenAmount);
        }

        BalancerPool(balVault).joinPool(balancerPoolId, address(this), msg.sender, request);
    }

    function _exercise(uint256 amount, uint256 maxPaymentAmount, address recipient)
        internal
        virtual
        returns (uint256 paymentAmount)
    {
        if (amount == 0) return 0;

        oToken.transferFrom(msg.sender, address(0), amount);

        paymentAmount = amount.mulWadUp(oracle.getPrice());
        if (paymentAmount > maxPaymentAmount) revert Exercise__SlippageTooHigh();

        paymentToken.safeTransferFrom(msg.sender, treasury, paymentAmount);
        underlyingToken.mint(recipient, amount);

        emit Exercised(msg.sender, recipient, amount, paymentAmount);
    }

    function setBalancerVault(address _balVault) external onlyOwner {
        balVault = _balVault;
    }

    function setOtherTokenAddress(address _otherTokenAddress) external onlyOwner {
        otherTokenAddress = _otherTokenAddress;
    }

    function setWETHAddress(address _wethAddress) external onlyOwner {
        ethTokenAddress = _wethAddress;
    }
}
