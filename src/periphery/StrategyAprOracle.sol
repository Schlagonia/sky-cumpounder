// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStaking} from "../interfaces/IStaking.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";

contract StrategyAprOracle {

    address private constant UNI_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 router on Mainnet

    /// @notice The SKY governance token (ERC20) that the Vault holds.
    address public constant SKY =
        0x56072C95FAA701256059aa122697B133aDEd9279;

    /// @notice The USDS reward token (ERC20) earned by farming SKY.
    address public constant USDS =
        0xdC035D45d973E3EC169d2276DDab16f1e407384F;


    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta)
        external
        view
        returns (uint256)
    {
        IStaking farm = IStaking(IStrategyInterface(_strategy).FARM());

        if (block.timestamp > farm.periodFinish()) {
            return 0;
        }

        uint256 rewardRate = farm.rewardRate();

        // fetch staking token amount
        uint256 stakedAmount = uint256(int256(farm.totalSupply()) + _delta);

        // fetch price
        uint256 stakePrice = skyPrice();

        // calculate apr
        uint256 tvl = stakePrice * stakedAmount;

        uint256 rewardsPerYearUsd = (rewardRate * 1e18 * 365 days);

        return tvl > 0 ? (rewardsPerYearUsd * 1e18) / tvl : 0; // apr in 1e18 (1e18=100%)
    }

    function skyPrice() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(SKY);
        path[1] = address(USDS);

        uint256[] memory amounts = IUniswapV2Router(UNI_V2_ROUTER).getAmountsOut(1e18, path);

        return amounts[1];
    }
}
