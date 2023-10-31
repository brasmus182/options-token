// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {BaseExercise} from "./BaseExercise.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IVault as BalancerVault, IAsset} from "../interfaces/IBalancerVault.sol";
import {IBalancer2TokensPool} from "../interfaces/IBalancer2TokensPool.sol";
import {VestingWallet} from "../utils/VestingWallet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {OptionsToken} from "../OptionsToken.sol";

struct BOathExerciseParams {
    uint256 paymentTokenAmount;
    uint256 minBPTOut;
}

/// @title Balancer 2 Token Pool Lock Exercise Contract
/// @author @bigbadbeard, @lookee, @eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by locking the underlying token into a Balancer pool for a given duration.
/// @notice Users must supply the payment token to create the Balancer position.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract Exercise is BaseExercise, Owned {
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
    event LockCreated(address indexed by, address wallet);
    event SetOracle(IOracle indexed newOracle);

    /// Immutable parameters
    ERC20 public immutable paymentToken;
    ERC20 public immutable underlyingToken;

    /// Storage variables
    IOracle public oracle;
    address public balVault;
    uint256 public oracleVarianceThresholdBPS;
    uint64 public lockDuration;
    address private vestingWalletImpl;
    bytes32 public balancerPoolId;

    bool private underlyingIsToken0;
    uint256[] private poolWeights;

    constructor(
        OptionsToken oToken_,
        address owner_,
        ERC20 paymentToken_,
        ERC20 underlyingToken_,
        bytes32 balancerPoolId_,
        address balVault_,
        IOracle oracle_,
        uint64 lockDuration_,
        uint256 oracleVarianceThresholdBPS_
    ) BaseExercise(oToken_) Owned(owner_) {
        oToken = oToken_;
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;
        balancerPoolId = balancerPoolId_;
        balVault = balVault_;
        oracle = oracle_;
        lockDuration = lockDuration_;
        oracleVarianceThresholdBPS = oracleVarianceThresholdBPS_;

        vestingWalletImpl = address(new VestingWallet());
        underlyingIsToken0 = address(underlyingToken_) < address(paymentToken_);
        (address _pool, ) = BalancerVault(balVault_).getPool(balancerPoolId_);
        poolWeights = IBalancer2TokensPool(_pool).getNormalizedWeights();

        emit SetOracle(oracle_);
    }

    /// External functions
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        override
        onlyOToken
        returns (uint256 paymentAmount)
    {
        return _exercise(from, amount, recipient, params);
    }

    /// Owner functions
    function setOracle(IOracle oracle_) external onlyOwner {
        oracle = oracle_;
        emit SetOracle(oracle_);
    }

    // New function to set Balancer's Pool ID
    function setBalancerVaultId(bytes32 _poolId) external onlyOwner {
        balancerPoolId = _poolId;
    }

    /// The function to Zap into the 80%/20% Token/ETH pool in Balancer
    function zapIntoBalancerPool(address user, uint256 tokenAmount, uint256 paymentAmount, uint256 minBPTOut, address to) internal {
        require(balancerPoolId != bytes32(0), "Balancer Pool ID not set");


        // check if user inputted amount is close enough to oracle price
        // the oracle price is token1 in terms of token0, 1:1 ratio
        uint256 oraclePrice = oracle.getPrice();
        // we must convert the tokens ratio into the pool's ratio by its weights
        // invert calculation if underlying is token1
        uint256 oracleAmountEstimate;
        if (underlyingIsToken0) {
            uint256 priceInPoolRatio = oraclePrice * poolWeights[0] / poolWeights[1];
            oracleAmountEstimate = tokenAmount.divWadDown(priceInPoolRatio);
        } else {
            uint256 priceInPoolRatio = oraclePrice * poolWeights[1] / poolWeights[0];
            oracleAmountEstimate = tokenAmount.mulWadDown(priceInPoolRatio);
        }

        uint256 threshold = oracleAmountEstimate * oracleVarianceThresholdBPS / 10000;
        if (
            oracleAmountEstimate > paymentAmount && oracleAmountEstimate - paymentAmount > threshold
            || oracleAmountEstimate < paymentAmount && paymentAmount- oracleAmountEstimate > threshold
        ) revert Exercise__OraclePriceVariance();

        uint256[] memory amountsIn = new uint256[](2);
        IAsset[] memory assets = new IAsset[](2);

        if (underlyingIsToken0) {
            amountsIn[0] = tokenAmount;
            amountsIn[1] = paymentAmount;

            assets[0] = IAsset(address(underlyingToken));
            assets[1] = IAsset(address(paymentToken));
        } else {
            amountsIn[1] = tokenAmount;
            amountsIn[0] = paymentAmount;

            assets[1] = IAsset(address(underlyingToken));
            assets[0] = IAsset(address(paymentToken));
        }

        bytes memory userData = abi.encode(uint8(1), amountsIn, minBPTOut); // uint8(1) represents JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT

        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: amountsIn, 
            userData: userData,
            fromInternalBalance: false
        });

        paymentToken.safeTransferFrom(user, address(this), paymentAmount);

        // Ensure enough allowance for both tokens
        underlyingToken.approve(balVault, paymentAmount);
        underlyingToken.approve(balVault, tokenAmount);

        address vestingWallet = _createVestingWallet(to);

        BalancerVault(balVault).joinPool(balancerPoolId, address(this), vestingWallet, request);
        emit LockCreated(user, vestingWallet);
    }
    
    function _createVestingWallet(address beneficiary)
        internal
        returns (address wallet)
    {
        wallet = Clones.clone(vestingWalletImpl);
        VestingWallet(payable(wallet)).initialize(beneficiary, lockDuration);
    }


    function _exercise(address from, uint256 amount, address recipient, bytes memory params)
        internal
        virtual
        returns (uint256 paymentAmount)
    {
        if (amount == 0) return 0;
        BOathExerciseParams memory _params = abi.decode(params, (BOathExerciseParams));
        oToken.transferFrom(msg.sender, address(0), amount);

        zapIntoBalancerPool(from, amount, _params.paymentTokenAmount, _params.minBPTOut, recipient);
        
        emit Exercised(from, recipient, amount, paymentAmount);
    }

    function setBalancerVault(address _balVault) external onlyOwner {
        balVault = _balVault;
    }

}
