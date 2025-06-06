// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILockstakeEngine} from "./interfaces/ILockstakeEngine.sol";
import {IUniswapV2Router} from "./interfaces/IUniswapV2Router.sol";
import {IStaking} from "./interfaces/IStaking.sol";

/// @title StrategySKYLockstake
/// @notice A Yearn V3 TokenizedStrategy that:
///         1) Opens URN #0 on LockstakeEngine for itself and selects the USDS farm.
///         2) Locks SKY → USDS farm via LockstakeEngine.lock(...).
///         3) Periodically claims USDS rewards, swaps USDS→SKY, and re-locks SKY to compound.
///         4) Frees SKY on withdrawals.
///
contract SkyCumpounder is BaseHealthCheck {
    using SafeERC20 for ERC20;

    /// @notice Which URN index we use for this strategy (we fix to 0).
    uint256 public constant URN_INDEX = 0;

    /// @notice Uniswap V2 router address for swapping USDS → SKY.
    address private constant UNI_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 router on Mainnet

    /// @notice The SKY governance token (ERC20) that the Vault holds.
    ERC20 public constant SKY =
        ERC20(0x56072C95FAA701256059aa122697B133aDEd9279);

    /// @notice The USDS reward token (ERC20) earned by farming SKY.
    ERC20 public constant USDS =
        ERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    /// @notice MakerDAO’s LockstakeEngine contract address.
    ILockstakeEngine public immutable LOCK_STAKE_ENGINE;

    /// @notice The farm contract address for USDS rewards (selected via selectFarm).

    IStaking public immutable FARM;

    address public immutable URN;

    ///@notice yearn's referral code
    uint16 public referral = 1007;

    address public voteDelegate;

    uint256 public minAmountToSell = 10e18;

    constructor(address _lockstakeEngine, address _usdsFarm)
        BaseHealthCheck(address(SKY), "Sky Cumpounder")
    {
        LOCK_STAKE_ENGINE = ILockstakeEngine(_lockstakeEngine);
        FARM = IStaking(_usdsFarm);

        // Approve SKY → LockstakeEngine for unlimited locking.
        SKY.forceApprove(_lockstakeEngine, type(uint256).max);

        // Approve USDS → UniswapV2 Router for unlimited swapping.
        USDS.forceApprove(UNI_V2_ROUTER, type(uint256).max);

        // 1) Open URN #0 for this strategy address.
        URN = LOCK_STAKE_ENGINE.open(URN_INDEX);

        // 2) Select the USDS farm for URN #0 (so that lock(...) stakes directly into usdsFarm).
        LOCK_STAKE_ENGINE.selectFarm(
            address(this),
            URN_INDEX,
            _usdsFarm,
            referral
        );
    }

    /// @dev  Deploys new SKY into LockstakeEngine (automatically staking to USDS farm).
    /// @param assets  The amount of SKY (in wei) received from the Vault to lock.
    function _deployFunds(uint256 assets) internal override {
        LOCK_STAKE_ENGINE.lock(address(this), URN_INDEX, assets, referral);
    }

    /// @dev  Frees up to `assets` SKY from LockstakeEngine (unstaking from farm → UNLOCK).
    /// @param assets  The amount of SKY (in wei) to free/withdraw back to Vault.
    function _freeFunds(uint256 assets) internal override {
        LOCK_STAKE_ENGINE.free(address(this), URN_INDEX, address(this), assets);
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        LOCK_STAKE_ENGINE.getReward(
            address(this),
            URN_INDEX,
            address(FARM),
            address(this)
        );

        uint256 usdsBal = USDS.balanceOf(address(this));
        if (usdsBal > minAmountToSell) {
            _uniV2swapFrom(address(USDS), address(SKY), usdsBal, 0);
        }

        uint256 newSky = SKY.balanceOf(address(this));
        if (newSky > 0) {
            LOCK_STAKE_ENGINE.lock(address(this), URN_INDEX, newSky, referral);
        }

        _totalAssets = estimatedTotalAssets();
    }

    function _uniV2swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal {
        IUniswapV2Router(UNI_V2_ROUTER).swapExactTokensForTokens(
            _amountIn,
            _minAmountOut,
            _getTokenOutPath(_from, _to),
            address(this),
            block.timestamp
        );
    }

    function _getTokenOutPath(address _tokenIn, address _tokenOut)
        internal
        view
        virtual
        returns (address[] memory _path)
    {
        _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = _tokenOut;
    }

    /// @dev  Returns an approximate value of total assets (SKY) under management:
    ///       what’s currently staked in URN #0 plus any SKY already sitting in the contract.
    function estimatedTotalAssets() public view returns (uint256) {
        // Locked & staked SKY in URN #0:
        uint256 stakedSky = balanceOfStake();
        // Plus any SKY sitting idle in this contract:
        uint256 idleSky = SKY.balanceOf(address(this));
        return stakedSky + idleSky;
    }

    function balanceOfStake() public view returns (uint256) {
        return FARM.balanceOf(URN);
    }

    /**
     * @notice Set the minimum amount of rewardsToken to sell
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(uint256 _minAmountToSell)
        external
        onlyManagement
    {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Set the referral code for staking.
     * @param _referral uint16 referral code
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    function setVoteDelegate(address _voteDelegate) external onlyManagement {
        voteDelegate = _voteDelegate;

        LOCK_STAKE_ENGINE.selectVoteDelegate(
            address(this),
            URN_INDEX,
            voteDelegate
        );
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }
}
