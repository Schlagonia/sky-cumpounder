// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @dev  Minimal Uniswap V2 router interface for swapping USDS → SKY.
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}
