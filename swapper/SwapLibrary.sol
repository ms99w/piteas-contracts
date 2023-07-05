// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../libraries/PitERC20.sol";
import "./interfaces/ISwapper.sol";

library SwapLibrary {
    using PitERC20 for IERC20;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    error UnsupportedRouter();

    enum ExchangeType {
        Unknown,
        Wrapper,
        UniswapV2,
        Solidly,
        UniswapV3,
        Balancer
    }

    function swap(
        ExchangeType self,
        uint256 deadline,
        address routerAddr,
        bytes memory data
    ) internal returns (uint256 returnAmount) {
        if (self == ExchangeType.Wrapper) {
            returnAmount = on_wrapper_eth(data);
        }
        else if (self == ExchangeType.UniswapV2) {
            returnAmount = on_swap_uniswapv2(routerAddr, deadline, data);
        }
        else if (self == ExchangeType.Solidly) {
            returnAmount = on_swap_solidly(routerAddr, deadline, data);
        }
        else if (self == ExchangeType.UniswapV3) {
            returnAmount = on_swap_uniswapv3(routerAddr, deadline, data);
        }
        else if (self == ExchangeType.Balancer) {
            returnAmount = on_swap_balancer(routerAddr, deadline, data);
        }
        else{
            revert UnsupportedRouter();
        }
    }

    function on_wrapper_eth(bytes memory data) private returns (uint256) {
        (uint256 amount, bool isWrap) = abi.decode(data, (uint256, bool));
        isWrap ? PitERC20.pDeposit(amount) : PitERC20.pWithdraw(amount);
        return amount;
    }

    function on_swap_uniswapv2(address routerAddr, uint256 deadline, bytes memory data) private returns (uint256) {
        IUniswapV2 router = IUniswapV2(routerAddr);
        (uint256 amount, IERC20 tokenIn, IERC20 tokenOut) = abi.decode(data, (uint256, IERC20, IERC20));
        amount = tokenIn.pAmountFixer(amount);
        address[] memory paths = new address[](2);
        paths[0] = address(tokenIn);
        paths[1] = address(tokenOut);
        tokenIn.pApprove(routerAddr, amount);
        uint256[] memory amounts = router.swapExactTokensForTokens(amount, 1, paths, address(this), deadline);
        return amounts[1];
    }

    function on_swap_solidly(address routerAddr, uint256 deadline, bytes memory data) private returns (uint256) {
        ISolidly router = ISolidly(routerAddr);
        (uint256 amount, IERC20 tokenIn, IERC20 tokenOut, bool isStable) = abi.decode(data, (uint256, IERC20, IERC20, bool));
        amount = tokenIn.pAmountFixer(amount);
        ISolidly.route[] memory paths = new ISolidly.route[](1);
        paths[0] = ISolidly.route(address(tokenIn), address(tokenOut), isStable);
        tokenIn.pApprove(routerAddr, amount);
        uint256[] memory amounts = router.swapExactTokensForTokens(amount, 1, paths, address(this), deadline);
        return amounts[1];
    }

    function on_swap_uniswapv3(address routerAddr, uint256, bytes memory data) private returns (uint256) {
        IUniswapV3 router = IUniswapV3(routerAddr);
        (uint256 amount, IERC20 tokenIn, IERC20 tokenOut, uint24 fee) = abi.decode(data, (uint256, IERC20, IERC20, uint24));
        amount = tokenIn.pAmountFixer(amount);
        tokenIn.pApprove(routerAddr, amount);
        return router.exactInputSingle(IUniswapV3.ExactInputSingleParams(address(tokenIn), address(tokenOut), fee, address(this), amount, 0, 0));
    }

    function on_swap_balancer(address routerAddr, uint256 deadline, bytes memory data) private returns (uint256) {
        IBalancer router = IBalancer(routerAddr);
        (uint256 amount, IERC20 tokenIn, IERC20 tokenOut, bytes32 poolId) = abi.decode(data, (uint256, IERC20, IERC20, bytes32));
        amount = tokenIn.pAmountFixer(amount);
        tokenIn.pApprove(routerAddr, amount);
        return router.swap(IBalancer.SingleSwap(poolId,IBalancer.SwapKind.GIVEN_IN ,address(tokenIn), address(tokenOut), amount, bytes("")), IBalancer.FundManagement(address(this), false, payable(address(this)), false), 0, deadline);
    }

}