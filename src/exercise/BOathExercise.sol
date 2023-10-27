// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IVault as BalancerVault, IAsset} from "../interfaces/IBalancerVault.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {OptionsToken} from "../OptionsToken.sol";

struct BOathExerciseParams {
    uint256 ethAmount;
    uint256 minBPTOut;
}

/// @title Options Token Exercise Contract
/// @author @bigbadbeard, @lookee, @eidolon
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
    error Exercise__OraclePriceVariance();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);

    /// Immutable parameters
    ERC20 public immutable paymentToken;
    ERC20 public immutable underlyingToken;
    OptionsToken public immutable oToken;

    /// Storage variables
    IOracle public oracle;
    address public treasury;
    address public balVault;
    address public otherTokenAddress;
    address public weth;
    uint256 oracleVarianceThresholdBPS;

    // New state variable for Balancer's PoolId
    bytes32 public balancerPoolId;

    constructor(
        OptionsToken oToken_,
        address owner_,
        ERC20 paymentToken_,
        ERC20 underlyingToken_,
        IOracle oracle_,
        address treasury_,
        uint256 oracleVarianceThresholdBPS_
    ) Owned(owner_) {
        oToken = oToken_;
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;
        oracle = oracle_;
        treasury = treasury_;
        oracleVarianceThresholdBPS = oracleVarianceThresholdBPS_;

        // vestingWalletImpl = new VestingWallet();

        emit SetOracle(oracle_);
        emit SetTreasury(treasury_);
    }

    /// External functions
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        returns (uint256 paymentAmount)
    {
        return _exercise(from, amount, recipient, params);
    }

    function exercise(address from, uint256 amount, address recipient, bytes memory params, uint256 deadline)
        external
        virtual
        returns (uint256 paymentAmount)
    {
        if (block.timestamp > deadline) revert Exercise__PastDeadline();
        return _exercise(from, amount, recipient, params);
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
    function setBalancerVaultId(bytes32 _poolId) external onlyOwner {
        balancerPoolId = _poolId;
    }

    /// The function to Zap into the 80%/20% Token/ETH pool in Balancer
    function zapIntoBalancerPool(address user, uint256 tokenAmount, uint256 ethAmount, uint256 minBPTOut) internal {
        require(balancerPoolId != bytes32(0), "Balancer Pool ID not set");

        // check if user inputted amount is close enough to oracle price
        // the oracle price is eth in terms of oath, 1:1 ratio
        // we must convert the tokens ratio into 80:20
        uint256 oraclePrice = oracle.getPrice().mulWadUp(80/20);
        uint256 oracleAmountEstimate = tokenAmount.divWadDown(oraclePrice);
        uint256 threshold = oracleAmountEstimate * oracleVarianceThresholdBPS / 10000;
        if (
            oracleAmountEstimate > ethAmount && oracleAmountEstimate - ethAmount > threshold
            || oracleAmountEstimate < ethAmount && ethAmount - oracleAmountEstimate > threshold
        ) revert Exercise__OraclePriceVariance();

        uint256[] memory amountsIn = new uint256[](2);
        IAsset[] memory assets = new IAsset[](2);

        if (weth > address(underlyingToken)) {
            amountsIn[0] = tokenAmount;
            amountsIn[1] = ethAmount;

            assets[0] = IAsset(address(underlyingToken));
            assets[1] = IAsset(weth);
        } else {
            amountsIn[1] = tokenAmount;
            amountsIn[0] = ethAmount;

            assets[1] = IAsset(address(underlyingToken));
            assets[0] = IAsset(weth);
        }

        bytes memory userData = abi.encode(uint8(1), amountsIn, minBPTOut); // uint8(1) represents JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT

        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: amountsIn, 
            userData: userData,
            fromInternalBalance: false
        });

        ERC20(weth).safeTransferFrom(user, address(this), ethAmount);

        // Ensure enough allowance for both tokens
        ERC20(weth).approve(balVault, ethAmount);
        ERC20(underlyingToken).approve(balVault, tokenAmount);

        BalancerVault(balVault).joinPool(balancerPoolId, address(this), msg.sender, request);
    }

    function _exercise(address from, uint256 amount, address recipient, bytes memory params)
        internal
        virtual
        returns (uint256 paymentAmount)
    {
        if (amount == 0) return 0;
        BOathExerciseParams memory _params = abi.decode(params, (BOathExerciseParams));
        oToken.transferFrom(msg.sender, address(0), amount);

        zapIntoBalancerPool(from, amount, _params.ethAmount, _params.minBPTOut);
        
        emit Exercised(from, recipient, amount, paymentAmount);
    }

    function setBalancerVault(address _balVault) external onlyOwner {
        balVault = _balVault;
    }

    function setOtherTokenAddress(address _otherTokenAddress) external onlyOwner {
        otherTokenAddress = _otherTokenAddress;
    }

    function setWETHAddress(address _wethAddress) external onlyOwner {
        weth = _wethAddress;
    }
}
