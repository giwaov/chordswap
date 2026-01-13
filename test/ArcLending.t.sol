// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/lending/ArcLendingPool.sol";
import "../src/lending/InterestRateModel.sol";
import "../src/lending/ArcLendToken.sol";
import "../src/lending/FlashLoanReceivers.sol";
import "../src/lending/MockERC20.sol";
import "../src/PriceOracle.sol";

/**
 * @title ArcLendingTest
 * @notice Comprehensive test suite for Arc Lending Protocol
 */
contract ArcLendingTest is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    ArcLendingPool public pool;
    InterestRateModel public rateModel;
    PriceOracle public oracle;
    
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public liquidator = makeAddr("liquidator");
    
    uint256 constant PRECISION = 1e18;
    
    // Market parameters
    uint256 constant USDC_CF = 85e16;
    uint256 constant USDC_LT = 90e16;
    uint256 constant USDC_RF = 10e16;
    
    uint256 constant WETH_CF = 75e16;
    uint256 constant WETH_LT = 80e16;
    uint256 constant WETH_RF = 15e16;
    
    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════
    
    function setUp() public {
        // Deploy oracle
        oracle = new PriceOracle();
        
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        
        // Set prices (18 decimals)
        oracle.setPrice(address(usdc), 1e18);      // $1
        oracle.setPrice(address(weth), 3500e18);   // $3,500
        oracle.setPrice(address(wbtc), 95000e18);  // $95,000
        
        // Deploy lending pool
        pool = new ArcLendingPool(address(oracle));
        
        // List markets
        pool.listMarket(
            address(usdc),
            "Arc Lending USDC",
            "aUSDC",
            USDC_CF,
            USDC_LT,
            USDC_RF
        );
        
        pool.listMarket(
            address(weth),
            "Arc Lending WETH",
            "aWETH",
            WETH_CF,
            WETH_LT,
            WETH_RF
        );
        
        // Mint tokens to users
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(charlie, 100_000e6);
        usdc.mint(liquidator, 100_000e6);
        
        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);
        weth.mint(charlie, 100e18);
        
        // Approve lending pool
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        weth.approve(address(pool), type(uint256).max);
        
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        weth.approve(address(pool), type(uint256).max);
        
        vm.prank(charlie);
        usdc.approve(address(pool), type(uint256).max);
        
        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SUPPLY TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Supply() public {
        uint256 supplyAmount = 10_000e6;
        
        vm.prank(alice);
        pool.supply(address(usdc), supplyAmount);
        
        // Check state
        (,uint256 totalSupply,,,,,,,,) = pool.getMarketInfo(address(usdc));
        assertEq(totalSupply, supplyAmount, "Total supply mismatch");
        
        // Check aToken balance
        (address aTokenAddr,,,,,,,,,) = pool.getMarketInfo(address(usdc));
        ArcLendToken aToken = ArcLendToken(aTokenAddr);
        assertGt(aToken.balanceOf(alice), 0, "Should have aTokens");
    }
    
    function test_SupplyMultipleUsers() public {
        vm.prank(alice);
        pool.supply(address(usdc), 10_000e6);
        
        vm.prank(bob);
        pool.supply(address(usdc), 20_000e6);
        
        (,uint256 totalSupply,,,,,,,,) = pool.getMarketInfo(address(usdc));
        assertEq(totalSupply, 30_000e6, "Total supply should be sum");
    }
    
    function test_RevertSupplyZero() public {
        vm.prank(alice);
        vm.expectRevert(ArcLendingPool.InvalidAmount.selector);
        pool.supply(address(usdc), 0);
    }
    
    function test_RevertSupplyUnlistedMarket() public {
        vm.prank(alice);
        vm.expectRevert(ArcLendingPool.MarketNotListed.selector);
        pool.supply(address(wbtc), 1000);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Withdraw() public {
        uint256 supplyAmount = 10_000e6;
        
        vm.startPrank(alice);
        pool.supply(address(usdc), supplyAmount);
        
        uint256 balanceBefore = usdc.balanceOf(alice);
        pool.withdraw(address(usdc), supplyAmount);
        uint256 balanceAfter = usdc.balanceOf(alice);
        
        assertEq(balanceAfter - balanceBefore, supplyAmount, "Should receive full amount");
        vm.stopPrank();
    }
    
    function test_WithdrawMax() public {
        vm.startPrank(alice);
        pool.supply(address(usdc), 10_000e6);
        
        pool.withdraw(address(usdc), type(uint256).max);
        
        (address aTokenAddr,,,,,,,,,) = pool.getMarketInfo(address(usdc));
        assertEq(ArcLendToken(aTokenAddr).balanceOf(alice), 0, "Should have no aTokens");
        vm.stopPrank();
    }
    
    function test_RevertWithdrawInsufficientLiquidity() public {
        // Alice supplies
        vm.prank(alice);
        pool.supply(address(usdc), 10_000e6);
        
        // Bob supplies WETH as collateral and borrows USDC
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 8_000e6);
        vm.stopPrank();
        
        // Alice tries to withdraw all (but Bob borrowed most of it)
        vm.prank(alice);
        vm.expectRevert(ArcLendingPool.InsufficientLiquidity.selector);
        pool.withdraw(address(usdc), 10_000e6);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BORROW TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Borrow() public {
        // Alice supplies USDC as liquidity
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        // Bob supplies WETH as collateral and borrows USDC
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18); // 10 WETH = $35,000
        pool.enableCollateral(address(weth));
        
        // With 75% LTV, can borrow up to $26,250
        uint256 borrowAmount = 20_000e6; // $20,000
        pool.borrow(address(usdc), borrowAmount);
        
        assertEq(usdc.balanceOf(bob), 100_000e6 + borrowAmount, "Should receive borrowed tokens");
        
        uint256 borrowBalance = pool.borrowBalance(bob, address(usdc));
        assertEq(borrowBalance, borrowAmount, "Borrow balance should match");
        vm.stopPrank();
    }
    
    function test_RevertBorrowInsufficientCollateral() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 1e18); // 1 WETH = $3,500
        pool.enableCollateral(address(weth));
        
        // With 75% LTV, can only borrow $2,625
        vm.expectRevert(ArcLendingPool.InsufficientCollateral.selector);
        pool.borrow(address(usdc), 5_000e6); // Try to borrow $5,000
        vm.stopPrank();
    }
    
    function test_RevertBorrowNoCollateral() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        // NOT enabling collateral
        
        vm.expectRevert(ArcLendingPool.InsufficientCollateral.selector);
        pool.borrow(address(usdc), 1_000e6);
        vm.stopPrank();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // REPAY TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Repay() public {
        // Setup borrow
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6);
        
        // Repay half
        pool.repay(address(usdc), 5_000e6);
        
        uint256 borrowBalance = pool.borrowBalance(bob, address(usdc));
        assertEq(borrowBalance, 5_000e6, "Should have half remaining");
        vm.stopPrank();
    }
    
    function test_RepayFull() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6);
        
        pool.repay(address(usdc), type(uint256).max);
        
        uint256 borrowBalance = pool.borrowBalance(bob, address(usdc));
        assertEq(borrowBalance, 0, "Should be fully repaid");
        vm.stopPrank();
    }
    
    function test_RepayBehalf() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6);
        vm.stopPrank();
        
        // Charlie repays on behalf of Bob
        vm.prank(charlie);
        pool.repayBehalf(bob, address(usdc), 5_000e6);
        
        uint256 borrowBalance = pool.borrowBalance(bob, address(usdc));
        assertEq(borrowBalance, 5_000e6, "Bob should have half remaining");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INTEREST TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_InterestAccrual() public {
        // Alice supplies
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        // Bob borrows
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6);
        vm.stopPrank();
        
        uint256 borrowBefore = pool.borrowBalance(bob, address(usdc));
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        uint256 borrowAfter = pool.borrowBalance(bob, address(usdc));
        
        assertGt(borrowAfter, borrowBefore, "Interest should accrue");
        
        // Check utilization is 20% (10k / 50k)
        // At 20% utilization: rate = 2% base + (20/80)*4% = 2% + 1% = 3% APR
        // Expected interest ~= 10_000 * 0.03 = 300
        uint256 interest = borrowAfter - borrowBefore;
        assertApproxEqRel(interest, 300e6, 0.1e18, "Interest should be ~3%");
    }
    
    function test_SupplyAPRIncreasesWithUtilization() public {
        vm.prank(alice);
        pool.supply(address(usdc), 100_000e6);
        
        // Low utilization
        (uint256 supplyAPR1,,) = pool.getMarketRates(address(usdc));
        
        // Increase utilization
        vm.startPrank(bob);
        pool.supply(address(weth), 50e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 50_000e6); // 50% utilization
        vm.stopPrank();
        
        (uint256 supplyAPR2,,) = pool.getMarketRates(address(usdc));
        
        assertGt(supplyAPR2, supplyAPR1, "Supply APR should increase with utilization");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HEALTH FACTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_HealthFactor() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18); // $35,000
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6); // $10,000
        vm.stopPrank();
        
        uint256 hf = pool.healthFactor(bob);
        
        // Collateral value (adjusted) = $35,000 * 0.80 = $28,000
        // Borrow value = $10,000
        // Health factor = 28,000 / 10,000 = 2.8
        assertApproxEqRel(hf, 2.8e18, 0.01e18, "Health factor should be ~2.8");
    }
    
    function test_HealthFactorDropsWithPriceChange() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 20_000e6);
        vm.stopPrank();
        
        uint256 hfBefore = pool.healthFactor(bob);
        
        // ETH price drops 30%
        oracle.setPrice(address(weth), 2450e18); // $3,500 -> $2,450
        
        uint256 hfAfter = pool.healthFactor(bob);
        
        assertLt(hfAfter, hfBefore, "Health factor should drop");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Liquidation() public {
        // Setup: Alice supplies USDC, Bob supplies WETH and borrows USDC
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18); // $35,000 worth
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 25_000e6); // Borrow close to max
        vm.stopPrank();
        
        // Get aToken for approvals
        (address aTokenAddr,,,,,,,,,) = pool.getMarketInfo(address(weth));
        vm.prank(bob);
        ArcLendToken(aTokenAddr).approve(address(pool), type(uint256).max);
        
        // ETH price drops - Bob becomes liquidatable
        oracle.setPrice(address(weth), 2000e18); // $3,500 -> $2,000
        
        uint256 hf = pool.healthFactor(bob);
        assertLt(hf, 1e18, "Should be liquidatable");
        
        // Liquidator repays some debt and seizes collateral
        vm.prank(liquidator);
        pool.liquidate(bob, address(usdc), address(weth), 10_000e6);
        
        // Check Bob's debt decreased
        uint256 newDebt = pool.borrowBalance(bob, address(usdc));
        assertLt(newDebt, 25_000e6, "Debt should decrease");
    }
    
    function test_RevertLiquidateHealthyPosition() public {
        vm.prank(alice);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 5_000e6); // Low borrow, healthy position
        vm.stopPrank();
        
        vm.prank(liquidator);
        vm.expectRevert(ArcLendingPool.HealthFactorOk.selector);
        pool.liquidate(bob, address(usdc), address(weth), 1_000e6);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FLASH LOAN TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_FlashLoan() public {
        // Supply liquidity
        vm.prank(alice);
        pool.supply(address(usdc), 100_000e6);
        
        // Deploy flash loan receiver
        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(address(pool));
        
        // Give receiver extra to pay fee
        usdc.mint(address(receiver), 1000e6);
        
        // Execute flash loan
        pool.flashLoan(
            address(usdc),
            50_000e6,
            address(receiver),
            ""
        );
        
        assertTrue(receiver.wasExecuted(), "Flash loan should execute");
    }
    
    function test_RevertFlashLoanNotRepaid() public {
        vm.prank(alice);
        pool.supply(address(usdc), 100_000e6);
        
        // Deploy bad receiver that doesn't repay
        BadFlashLoanReceiver badReceiver = new BadFlashLoanReceiver();
        
        vm.expectRevert(ArcLendingPool.FlashLoanFailed.selector);
        pool.flashLoan(
            address(usdc),
            50_000e6,
            address(badReceiver),
            ""
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // COLLATERAL MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_EnableDisableCollateral() public {
        vm.startPrank(alice);
        pool.supply(address(weth), 10e18);
        
        pool.enableCollateral(address(weth));
        
        // Now can borrow
        pool.supply(address(usdc), 10_000e6); // Add some USDC liquidity first
        vm.stopPrank();
        
        vm.prank(bob);
        pool.supply(address(usdc), 10_000e6);
        
        vm.startPrank(alice);
        pool.borrow(address(usdc), 1_000e6);
        
        // Repay and disable collateral
        pool.repay(address(usdc), type(uint256).max);
        pool.disableCollateral(address(weth));
        vm.stopPrank();
    }
    
    function test_RevertDisableCollateralWithBorrow() public {
        vm.prank(bob);
        pool.supply(address(usdc), 50_000e6);
        
        vm.startPrank(alice);
        pool.supply(address(weth), 10e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 10_000e6);
        
        vm.expectRevert(ArcLendingPool.InsufficientCollateral.selector);
        pool.disableCollateral(address(weth));
        vm.stopPrank();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INTEREST RATE MODEL TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_InterestRateModel() public {
        InterestRateModel model = new InterestRateModel();
        
        // Test at 0% utilization
        uint256 rate0 = model.getBorrowAPR(0, 100e18);
        assertApproxEqRel(rate0, 2e16, 0.001e18, "Base rate should be ~2%");
        
        // Test at 80% utilization (optimal)
        uint256 rate80 = model.getBorrowAPR(80e18, 100e18);
        assertApproxEqRel(rate80, 6e16, 0.01e18, "Rate at optimal should be ~6%");
        
        // Test at 100% utilization
        uint256 rate100 = model.getBorrowAPR(100e18, 100e18);
        assertApproxEqRel(rate100, 81e16, 0.01e18, "Rate at 100% should be ~81%");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_OnlyOwnerCanListMarket() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.listMarket(address(wbtc), "aWBTC", "aWBTC", 70e16, 75e16, 20e16);
    }
    
    function test_PauseProtocol() public {
        pool.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        pool.supply(address(usdc), 1000e6);
        
        pool.unpause();
        
        vm.prank(alice);
        pool.supply(address(usdc), 1000e6);
    }
    
    function test_WithdrawReserves() public {
        // Setup some reserves through interest
        vm.prank(alice);
        pool.supply(address(usdc), 100_000e6);
        
        vm.startPrank(bob);
        pool.supply(address(weth), 50e18);
        pool.enableCollateral(address(weth));
        pool.borrow(address(usdc), 50_000e6);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 365 days);
        pool.accrueInterest(address(usdc));
        
        (,,,uint256 reserves,,,,,,) = pool.getMarketInfo(address(usdc));
        assertGt(reserves, 0, "Should have reserves");
        
        address treasury = makeAddr("treasury");
        pool.withdrawReserves(address(usdc), reserves, treasury);
        
        assertGt(usdc.balanceOf(treasury), 0, "Treasury should receive reserves");
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

contract MockFlashLoanReceiver {
    using SafeERC20 for IERC20;
    
    address public pool;
    bool public wasExecuted;
    
    constructor(address _pool) {
        pool = _pool;
    }
    
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address,
        bytes calldata
    ) external {
        require(msg.sender == pool, "Only pool");
        wasExecuted = true;
        
        // Repay
        IERC20(asset).safeTransfer(pool, amount + fee);
    }
}

contract BadFlashLoanReceiver {
    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure {
        // Does nothing - doesn't repay
    }
}
