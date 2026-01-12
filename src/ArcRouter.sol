// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ArcFactory.sol";
import "./ArcPair.sol";

/**
 * @title ArcRouter
 * @dev Router contract for easy interaction with the AMM DEX on Arc Testnet
 * Provides functions for swapping tokens and managing liquidity
 */
contract ArcRouter {
    using SafeERC20 for IERC20;

    address public immutable factory;

    // Events
    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event LiquidityRemoved(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "ArcRouter: expired");
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    // ========== LIQUIDITY FUNCTIONS ==========

    /**
     * @dev Add liquidity to a pair
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Create pair if it doesn't exist
        if (ArcFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ArcFactory(factory).createPair(tokenA, tokenB);
        }
        
        (amountA, amountB) = _calculateLiquidityAmounts(
            tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin
        );
        
        address pair = ArcFactory(factory).getPair(tokenA, tokenB);
        
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        
        liquidity = ArcPair(pair).mint(to);
        
        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity);
    }

    /**
     * @dev Remove liquidity from a pair
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = ArcFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "ArcRouter: pair does not exist");
        
        // Transfer LP tokens to pair
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        
        // Burn LP tokens and receive underlying tokens
        (uint256 amount0, uint256 amount1) = ArcPair(pair).burn(to);
        
        // Sort amounts to match tokenA/tokenB order
        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        
        require(amountA >= amountAMin, "ArcRouter: insufficient A amount");
        require(amountB >= amountBMin, "ArcRouter: insufficient B amount");
        
        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB);
    }

    // ========== SWAP FUNCTIONS ==========

    /**
     * @dev Swap exact input amount for minimum output
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "ArcRouter: insufficient output amount");
        
        address pair = ArcFactory(factory).getPair(path[0], path[1]);
        IERC20(path[0]).safeTransferFrom(msg.sender, pair, amounts[0]);
        
        _swap(amounts, path, to);
    }

    /**
     * @dev Swap tokens for exact output amount
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "ArcRouter: excessive input amount");
        
        address pair = ArcFactory(factory).getPair(path[0], path[1]);
        IERC20(path[0]).safeTransferFrom(msg.sender, pair, amounts[0]);
        
        _swap(amounts, path, to);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @dev Get output amount for a given input
     */
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) 
        public 
        view 
        returns (uint256 amountOut) 
    {
        address pair = ArcFactory(factory).getPair(tokenIn, tokenOut);
        require(pair != address(0), "ArcRouter: pair does not exist");
        
        (uint112 reserve0, uint112 reserve1,) = ArcPair(pair).getReserves();
        (address token0,) = _sortTokens(tokenIn, tokenOut);
        
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == token0 
            ? (uint256(reserve0), uint256(reserve1)) 
            : (uint256(reserve1), uint256(reserve0));
            
        amountOut = ArcPair(pair).getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @dev Get input amount for a given output
     */
    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut) 
        public 
        view 
        returns (uint256 amountIn) 
    {
        address pair = ArcFactory(factory).getPair(tokenIn, tokenOut);
        require(pair != address(0), "ArcRouter: pair does not exist");
        
        (uint112 reserve0, uint112 reserve1,) = ArcPair(pair).getReserves();
        (address token0,) = _sortTokens(tokenIn, tokenOut);
        
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == token0 
            ? (uint256(reserve0), uint256(reserve1)) 
            : (uint256(reserve1), uint256(reserve0));
            
        amountIn = ArcPair(pair).getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /**
     * @dev Get amounts out for a path
     */
    function getAmountsOut(uint256 amountIn, address[] memory path) 
        public 
        view 
        returns (uint256[] memory amounts) 
    {
        require(path.length >= 2, "ArcRouter: invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = getAmountOut(amounts[i], path[i], path[i + 1]);
        }
    }

    /**
     * @dev Get amounts in for a path
     */
    function getAmountsIn(uint256 amountOut, address[] memory path) 
        public 
        view 
        returns (uint256[] memory amounts) 
    {
        require(path.length >= 2, "ArcRouter: invalid path");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        
        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = getAmountIn(amounts[i], path[i - 1], path[i]);
        }
    }

    /**
     * @dev Get pair info
     */
    function getPairInfo(address tokenA, address tokenB) 
        external 
        view 
        returns (
            address pair,
            uint256 reserveA,
            uint256 reserveB,
            uint256 totalSupply
        ) 
    {
        pair = ArcFactory(factory).getPair(tokenA, tokenB);
        if (pair != address(0)) {
            (uint112 reserve0, uint112 reserve1,) = ArcPair(pair).getReserves();
            (address token0,) = _sortTokens(tokenA, tokenB);
            (reserveA, reserveB) = tokenA == token0 
                ? (uint256(reserve0), uint256(reserve1)) 
                : (uint256(reserve1), uint256(reserve0));
            totalSupply = ArcPair(pair).totalSupply();
        }
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _calculateLiquidityAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        address pair = ArcFactory(factory).getPair(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1,) = ArcPair(pair).getReserves();
        
        if (reserve0 == 0 && reserve1 == 0) {
            // First liquidity provision
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            (address token0,) = _sortTokens(tokenA, tokenB);
            (uint256 reserveA, uint256 reserveB) = tokenA == token0 
                ? (uint256(reserve0), uint256(reserve1)) 
                : (uint256(reserve1), uint256(reserve0));
            
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "ArcRouter: insufficient B amount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal <= amountADesired, "ArcRouter: excessive A amount");
                require(amountAOptimal >= amountAMin, "ArcRouter: insufficient A amount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            
            (uint256 amount0Out, uint256 amount1Out) = input == token0 
                ? (uint256(0), amountOut) 
                : (amountOut, uint256(0));
            
            address to = i < path.length - 2 
                ? ArcFactory(factory).getPair(output, path[i + 2]) 
                : _to;
            
            ArcPair(ArcFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "ArcRouter: identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ArcRouter: zero address");
    }
}
