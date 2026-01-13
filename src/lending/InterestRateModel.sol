// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InterestRateModel
 * @author ChordSwap
 * @notice Dynamic interest rate model based on utilization rate
 * @dev Implements a kinked interest rate curve similar to Compound/Aave
 * 
 * Interest Rate Curve:
 * - Below optimal utilization: gentle slope
 * - Above optimal utilization: steep slope (incentivizes repayment)
 */
contract InterestRateModel {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // ═══════════════════════════════════════════════════════════════════════
    // RATE MODEL PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Optimal utilization rate (80%)
    uint256 public constant OPTIMAL_UTILIZATION = 80e16; // 0.80 * 1e18
    
    /// @notice Base borrow rate when utilization is 0 (2% APR)
    uint256 public constant BASE_RATE = 2e16; // 0.02 * 1e18
    
    /// @notice Rate slope below optimal utilization (4% at optimal)
    uint256 public constant SLOPE_1 = 4e16; // 0.04 * 1e18
    
    /// @notice Rate slope above optimal utilization (steep - 75% additional)
    uint256 public constant SLOPE_2 = 75e16; // 0.75 * 1e18
    
    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate utilization rate
     * @param totalBorrows Total borrowed amount
     * @param totalSupply Total supplied amount (available + borrowed)
     * @return Utilization rate in 1e18 precision
     */
    function getUtilizationRate(
        uint256 totalBorrows,
        uint256 totalSupply
    ) public pure returns (uint256) {
        if (totalSupply == 0) return 0;
        return (totalBorrows * PRECISION) / totalSupply;
    }
    
    /**
     * @notice Calculate borrow rate per second
     * @param totalBorrows Total borrowed amount
     * @param totalSupply Total supplied amount
     * @return Borrow rate per second in 1e18 precision
     */
    function getBorrowRate(
        uint256 totalBorrows,
        uint256 totalSupply
    ) public pure returns (uint256) {
        uint256 utilization = getUtilizationRate(totalBorrows, totalSupply);
        
        uint256 annualRate;
        
        if (utilization <= OPTIMAL_UTILIZATION) {
            // Below optimal: base + (utilization / optimal) * slope1
            annualRate = BASE_RATE + (utilization * SLOPE_1) / OPTIMAL_UTILIZATION;
        } else {
            // Above optimal: base + slope1 + ((utilization - optimal) / (1 - optimal)) * slope2
            uint256 excessUtilization = utilization - OPTIMAL_UTILIZATION;
            uint256 maxExcess = PRECISION - OPTIMAL_UTILIZATION;
            annualRate = BASE_RATE + SLOPE_1 + (excessUtilization * SLOPE_2) / maxExcess;
        }
        
        // Convert annual rate to per-second rate
        return annualRate / SECONDS_PER_YEAR;
    }
    
    /**
     * @notice Calculate supply rate per second
     * @param totalBorrows Total borrowed amount
     * @param totalSupply Total supplied amount
     * @param reserveFactor Protocol reserve factor (1e18 = 100%)
     * @return Supply rate per second in 1e18 precision
     */
    function getSupplyRate(
        uint256 totalBorrows,
        uint256 totalSupply,
        uint256 reserveFactor
    ) public pure returns (uint256) {
        uint256 utilization = getUtilizationRate(totalBorrows, totalSupply);
        uint256 borrowRate = getBorrowRate(totalBorrows, totalSupply);
        
        // supplyRate = borrowRate * utilization * (1 - reserveFactor)
        uint256 rateToSuppliers = (PRECISION - reserveFactor);
        return (borrowRate * utilization * rateToSuppliers) / (PRECISION * PRECISION);
    }
    
    /**
     * @notice Get annual percentage rate for borrowing
     * @param totalBorrows Total borrowed amount
     * @param totalSupply Total supplied amount
     * @return APR in 1e18 precision (1e18 = 100%)
     */
    function getBorrowAPR(
        uint256 totalBorrows,
        uint256 totalSupply
    ) external pure returns (uint256) {
        return getBorrowRate(totalBorrows, totalSupply) * SECONDS_PER_YEAR;
    }
    
    /**
     * @notice Get annual percentage rate for supplying
     * @param totalBorrows Total borrowed amount
     * @param totalSupply Total supplied amount
     * @param reserveFactor Protocol reserve factor
     * @return APR in 1e18 precision (1e18 = 100%)
     */
    function getSupplyAPR(
        uint256 totalBorrows,
        uint256 totalSupply,
        uint256 reserveFactor
    ) external pure returns (uint256) {
        return getSupplyRate(totalBorrows, totalSupply, reserveFactor) * SECONDS_PER_YEAR;
    }
    
    /**
     * @notice Calculate interest accrued over a time period
     * @param principal Principal amount
     * @param ratePerSecond Interest rate per second
     * @param timeElapsed Time elapsed in seconds
     * @return Interest accrued
     */
    function calculateInterest(
        uint256 principal,
        uint256 ratePerSecond,
        uint256 timeElapsed
    ) external pure returns (uint256) {
        // Simple interest: principal * rate * time
        // For more accuracy, compound interest could be used
        return (principal * ratePerSecond * timeElapsed) / PRECISION;
    }
    
    /**
     * @notice Calculate compound interest using approximation
     * @param principal Principal amount
     * @param ratePerSecond Interest rate per second (1e18 precision)
     * @param timeElapsed Time elapsed in seconds
     * @return New principal after compound interest
     */
    function calculateCompoundInterest(
        uint256 principal,
        uint256 ratePerSecond,
        uint256 timeElapsed
    ) external pure returns (uint256) {
        if (timeElapsed == 0) return principal;
        if (ratePerSecond == 0) return principal;
        
        // Use Taylor series approximation for e^(rt)
        // e^x ≈ 1 + x + x²/2 + x³/6 for small x
        uint256 rt = ratePerSecond * timeElapsed;
        
        // First term: principal
        uint256 result = principal;
        
        // Second term: principal * rt
        result += (principal * rt) / PRECISION;
        
        // Third term: principal * rt² / 2
        uint256 rtSquared = (rt * rt) / PRECISION;
        result += (principal * rtSquared) / (2 * PRECISION);
        
        // Fourth term: principal * rt³ / 6
        uint256 rtCubed = (rtSquared * rt) / PRECISION;
        result += (principal * rtCubed) / (6 * PRECISION);
        
        return result;
    }
}
