// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ArcFactory.sol";
import "../src/ArcPair.sol";
import "../src/ArcRouter.sol";
import "../src/ArcToken.sol";

contract ArcDexTest is Test {
    ArcFactory public factory;
    ArcRouter public router;
    ArcToken public tokenA;
    ArcToken public tokenB;
    
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        // Deploy factory and router
        factory = new ArcFactory(owner);
        router = new ArcRouter(address(factory));
        
        // Deploy test tokens
        tokenA = new ArcToken("Token A", "TKNA", 18, 1_000_000);
        tokenB = new ArcToken("Token B", "TKNB", 18, 1_000_000);
        
        // Transfer some tokens to users
        tokenA.transfer(user1, 100_000 * 1e18);
        tokenB.transfer(user1, 100_000 * 1e18);
        tokenA.transfer(user2, 100_000 * 1e18);
        tokenB.transfer(user2, 100_000 * 1e18);
    }

    // ========== FACTORY TESTS ==========

    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        
        assertTrue(pair != address(0), "Pair should be created");
        assertEq(factory.allPairsLength(), 1, "Should have 1 pair");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair, "getPair should return correct address");
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair, "getPair should work both ways");
    }

    function testCannotCreateDuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB));
        
        vm.expectRevert("ArcFactory: pair exists");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCannotCreatePairWithIdenticalAddresses() public {
        vm.expectRevert("ArcFactory: identical addresses");
        factory.createPair(address(tokenA), address(tokenA));
    }

    // ========== LIQUIDITY TESTS ==========

    function testAddLiquidity() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;
        
        // Approve router
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        
        // Add liquidity
        (uint256 actualA, uint256 actualB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        assertEq(actualA, amountA, "Amount A should match");
        assertEq(actualB, amountB, "Amount B should match");
        assertTrue(liquidity > 0, "Should receive LP tokens");
        
        // Check pair was created
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "Pair should exist");
        
        // Check LP balance
        assertEq(ArcPair(pair).balanceOf(owner), liquidity, "LP balance should match");
    }

    function testAddLiquidityTwice() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;
        
        // First liquidity
        tokenA.approve(address(router), amountA * 2);
        tokenB.approve(address(router), amountB * 2);
        
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        // Second liquidity
        (,, uint256 liquidity2) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        assertTrue(liquidity2 > 0, "Should receive LP tokens on second add");
    }

    function testRemoveLiquidity() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;
        
        // Add liquidity
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        // Get pair and approve
        address pair = factory.getPair(address(tokenA), address(tokenB));
        ArcPair(pair).approve(address(router), liquidity);
        
        uint256 balanceABefore = tokenA.balanceOf(owner);
        uint256 balanceBBefore = tokenB.balanceOf(owner);
        
        // Remove liquidity
        (uint256 removedA, uint256 removedB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        assertTrue(removedA > 0, "Should receive token A");
        assertTrue(removedB > 0, "Should receive token B");
        assertEq(tokenA.balanceOf(owner) - balanceABefore, removedA, "Balance A should increase");
        assertEq(tokenB.balanceOf(owner) - balanceBBefore, removedB, "Balance B should increase");
    }

    // ========== SWAP TESTS ==========

    function testSwapExactTokensForTokens() public {
        // Setup liquidity
        _addInitialLiquidity();
        
        uint256 swapAmount = 100 * 1e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        // Approve and swap
        vm.startPrank(user1);
        tokenA.approve(address(router), swapAmount);
        
        uint256 balanceBefore = tokenB.balanceOf(user1);
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            0, // min out
            path,
            user1,
            block.timestamp + 100
        );
        
        vm.stopPrank();
        
        assertEq(amounts[0], swapAmount, "Input amount should match");
        assertTrue(amounts[1] > 0, "Should receive output tokens");
        assertEq(tokenB.balanceOf(user1) - balanceBefore, amounts[1], "Balance should increase by output amount");
    }

    function testSwapTokensForExactTokens() public {
        // Setup liquidity
        _addInitialLiquidity();
        
        uint256 amountOut = 50 * 1e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        // Get quote for required input
        uint256[] memory expectedAmounts = router.getAmountsIn(amountOut, path);
        
        // Approve and swap
        vm.startPrank(user1);
        tokenA.approve(address(router), expectedAmounts[0] * 2); // Extra allowance
        
        uint256 balanceBBefore = tokenB.balanceOf(user1);
        uint256 balanceABefore = tokenA.balanceOf(user1);
        
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            expectedAmounts[0] * 2, // max in
            path,
            user1,
            block.timestamp + 100
        );
        
        vm.stopPrank();
        
        assertEq(amounts[1], amountOut, "Output amount should match");
        assertEq(tokenB.balanceOf(user1) - balanceBBefore, amountOut, "Should receive exact output");
        assertTrue(balanceABefore - tokenA.balanceOf(user1) > 0, "Should spend some token A");
    }

    function testGetAmountOut() public {
        _addInitialLiquidity();
        
        uint256 amountIn = 100 * 1e18;
        uint256 amountOut = router.getAmountOut(amountIn, address(tokenA), address(tokenB));
        
        // With 0.3% fee and equal reserves, output should be slightly less than input
        assertTrue(amountOut > 0, "Amount out should be positive");
        assertTrue(amountOut < amountIn, "Amount out should be less than input due to fee");
    }

    function testGetAmountIn() public {
        _addInitialLiquidity();
        
        uint256 amountOut = 50 * 1e18;
        uint256 amountIn = router.getAmountIn(amountOut, address(tokenA), address(tokenB));
        
        // With 0.3% fee, input should be more than output
        assertTrue(amountIn > amountOut, "Amount in should be more than output");
    }

    // ========== PAIR TESTS ==========

    function testGetReserves() public {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 5_000 * 1e18;
        
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        (uint112 reserve0, uint112 reserve1,) = ArcPair(pair).getReserves();
        
        // Reserves should match amounts (sorted by token address)
        assertTrue(reserve0 > 0, "Reserve0 should be positive");
        assertTrue(reserve1 > 0, "Reserve1 should be positive");
        assertEq(uint256(reserve0) + uint256(reserve1), amountA + amountB, "Total reserves should match");
    }

    function testConstantProductInvariant() public {
        _addInitialLiquidity();
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        (uint112 reserve0Before, uint112 reserve1Before,) = ArcPair(pair).getReserves();
        uint256 kBefore = uint256(reserve0Before) * uint256(reserve1Before);
        
        // Perform swap
        uint256 swapAmount = 100 * 1e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        vm.startPrank(user1);
        tokenA.approve(address(router), swapAmount);
        router.swapExactTokensForTokens(swapAmount, 0, path, user1, block.timestamp + 100);
        vm.stopPrank();
        
        (uint112 reserve0After, uint112 reserve1After,) = ArcPair(pair).getReserves();
        uint256 kAfter = uint256(reserve0After) * uint256(reserve1After);
        
        // K should be greater or equal (fees increase K)
        assertTrue(kAfter >= kBefore, "K should not decrease");
    }

    // ========== TOKEN TESTS ==========

    function testTokenFaucet() public {
        uint256 faucetAmount = 500 * 1e18;
        
        vm.prank(user2);
        tokenA.faucet(faucetAmount);
        
        assertTrue(tokenA.balanceOf(user2) > 100_000 * 1e18, "User should receive faucet tokens");
    }

    function testTokenFaucetLimit() public {
        uint256 tooMuch = 2000 * 1e18;
        
        vm.prank(user2);
        vm.expectRevert("Faucet: amount too large");
        tokenA.faucet(tooMuch);
    }

    // ========== HELPER FUNCTIONS ==========

    function _addInitialLiquidity() internal {
        uint256 amountA = 10_000 * 1e18;
        uint256 amountB = 10_000 * 1e18;
        
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            owner,
            block.timestamp + 100
        );
    }
}
