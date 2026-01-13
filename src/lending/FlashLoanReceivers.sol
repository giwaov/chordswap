// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FlashLoanReceiver
 * @author ChordSwap
 * @notice Example flash loan receiver for arbitrage and liquidations
 * @dev Implement your custom logic in executeOperation
 */
abstract contract FlashLoanReceiverBase {
    using SafeERC20 for IERC20;
    
    address public immutable lendingPool;
    
    constructor(address _lendingPool) {
        lendingPool = _lendingPool;
    }
    
    /**
     * @notice Called by lending pool during flash loan
     * @param asset The borrowed asset
     * @param amount The borrowed amount
     * @param fee The flash loan fee
     * @param initiator The address that initiated the flash loan
     * @param data Arbitrary data passed by initiator
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata data
    ) external virtual;
    
    /**
     * @notice Approve and repay flash loan
     */
    function _repayFlashLoan(address asset, uint256 amount, uint256 fee) internal {
        uint256 amountOwed = amount + fee;
        IERC20(asset).safeTransfer(lendingPool, amountOwed);
    }
}

/**
 * @title ArbitrageFlashLoan
 * @notice Flash loan receiver for DEX arbitrage
 */
contract ArbitrageFlashLoan is FlashLoanReceiverBase, Ownable {
    using SafeERC20 for IERC20;
    
    // DEX router interfaces
    struct SwapParams {
        address router;
        address[] path;
        uint256 amountOutMin;
    }
    
    event ArbitrageExecuted(
        address indexed token,
        uint256 borrowed,
        uint256 profit
    );
    
    constructor(address _lendingPool) 
        FlashLoanReceiverBase(_lendingPool) 
        Ownable(msg.sender) 
    {}
    
    /**
     * @notice Execute arbitrage using flash loan
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata data
    ) external override {
        require(msg.sender == lendingPool, "Only lending pool");
        require(initiator == owner(), "Only owner can initiate");
        
        // Decode swap parameters
        (SwapParams memory swap1, SwapParams memory swap2) = abi.decode(
            data, 
            (SwapParams, SwapParams)
        );
        
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Execute first swap
        IERC20(asset).approve(swap1.router, amount);
        _executeSwap(swap1.router, amount, swap1.amountOutMin, swap1.path);
        
        // Execute second swap (back to original token)
        uint256 intermediateBalance = IERC20(swap1.path[swap1.path.length - 1]).balanceOf(address(this));
        IERC20(swap1.path[swap1.path.length - 1]).approve(swap2.router, intermediateBalance);
        _executeSwap(swap2.router, intermediateBalance, swap2.amountOutMin, swap2.path);
        
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        
        // Repay flash loan
        _repayFlashLoan(asset, amount, fee);
        
        // Calculate profit
        uint256 profit = balanceAfter - balanceBefore - fee;
        
        emit ArbitrageExecuted(asset, amount, profit);
    }
    
    function _executeSwap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    ) internal {
        // Generic swap call - works with most DEX routers
        (bool success,) = router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                amountIn,
                amountOutMin,
                path,
                address(this),
                block.timestamp + 300
            )
        );
        require(success, "Swap failed");
    }
    
    /**
     * @notice Withdraw profits
     */
    function withdrawProfits(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), balance);
    }
    
    /**
     * @notice Rescue stuck tokens
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}

/**
 * @title LiquidationFlashLoan
 * @notice Flash loan receiver for liquidating undercollateralized positions
 */
contract LiquidationFlashLoan is FlashLoanReceiverBase, Ownable {
    using SafeERC20 for IERC20;
    
    struct LiquidationParams {
        address borrower;
        address collateralAsset;
        uint256 repayAmount;
    }
    
    event LiquidationExecuted(
        address indexed borrower,
        address indexed debtAsset,
        address indexed collateralAsset,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 profit
    );
    
    constructor(address _lendingPool) 
        FlashLoanReceiverBase(_lendingPool) 
        Ownable(msg.sender) 
    {}
    
    /**
     * @notice Execute liquidation using flash loan
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata data
    ) external override {
        require(msg.sender == lendingPool, "Only lending pool");
        require(initiator == owner(), "Only owner can initiate");
        
        // Decode liquidation parameters
        LiquidationParams memory params = abi.decode(data, (LiquidationParams));
        
        // Approve lending pool to take repayment
        IERC20(asset).approve(lendingPool, params.repayAmount);
        
        // Get collateral balance before
        uint256 collateralBefore = IERC20(params.collateralAsset).balanceOf(address(this));
        
        // Execute liquidation
        IArcLendingPool(lendingPool).liquidate(
            params.borrower,
            asset,
            params.collateralAsset,
            params.repayAmount
        );
        
        // Get collateral received
        uint256 collateralAfter = IERC20(params.collateralAsset).balanceOf(address(this));
        uint256 collateralSeized = collateralAfter - collateralBefore;
        
        // Swap collateral back to debt asset to repay flash loan
        // This would use a DEX in production
        // For now, assume we have enough of the debt asset
        
        // Repay flash loan
        _repayFlashLoan(asset, amount, fee);
        
        emit LiquidationExecuted(
            params.borrower,
            asset,
            params.collateralAsset,
            params.repayAmount,
            collateralSeized,
            0 // Calculate actual profit after swap
        );
    }
    
    /**
     * @notice Withdraw profits
     */
    function withdrawProfits(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), balance);
    }
}

/**
 * @title SimpleFlashLoanReceiver
 * @notice Simple example showing flash loan mechanics
 */
contract SimpleFlashLoanReceiver is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;
    
    event FlashLoanReceived(address asset, uint256 amount, uint256 fee);
    
    constructor(address _lendingPool) FlashLoanReceiverBase(_lendingPool) {}
    
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata data
    ) external override {
        require(msg.sender == lendingPool, "Only lending pool");
        
        emit FlashLoanReceived(asset, amount, fee);
        
        // Your custom logic here:
        // - Arbitrage between DEXes
        // - Self-liquidation
        // - Collateral swap
        // - Position adjustment
        
        // Example: just log and repay
        // In production, you would do something profitable here
        
        // Repay the flash loan
        _repayFlashLoan(asset, amount, fee);
    }
}

// Interface for liquidation call
interface IArcLendingPool {
    function liquidate(
        address borrower,
        address repayAsset,
        address collateralAsset,
        uint256 repayAmount
    ) external;
}
