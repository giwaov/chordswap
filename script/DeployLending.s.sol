// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/lending/ArcLendingPool.sol";
import "../src/lending/InterestRateModel.sol";
import "../src/lending/ArcLendToken.sol";
import "../src/lending/MockERC20.sol";
import "../src/PriceOracle.sol";

/**
 * @title DeployLending
 * @notice Deployment script for Arc Lending Protocol on Arc Testnet
 * 
 * Usage:
 *   source .env
 *   forge script script/DeployLending.s.sol:DeployLending \
 *     --rpc-url $ARC_TESTNET_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployLending is Script {
    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════
    
    // Market parameters (in 1e18 precision)
    uint256 constant USDC_COLLATERAL_FACTOR = 85e16;      // 85% LTV
    uint256 constant USDC_LIQUIDATION_THRESHOLD = 90e16;  // 90%
    uint256 constant USDC_RESERVE_FACTOR = 10e16;         // 10%
    
    uint256 constant WETH_COLLATERAL_FACTOR = 75e16;      // 75% LTV
    uint256 constant WETH_LIQUIDATION_THRESHOLD = 80e16;  // 80%
    uint256 constant WETH_RESERVE_FACTOR = 15e16;         // 15%
    
    uint256 constant WBTC_COLLATERAL_FACTOR = 70e16;      // 70% LTV
    uint256 constant WBTC_LIQUIDATION_THRESHOLD = 75e16;  // 75%
    uint256 constant WBTC_RESERVE_FACTOR = 20e16;         // 20%
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYED ADDRESSES (UPDATE AFTER DEPLOYMENT)
    // ═══════════════════════════════════════════════════════════════════════
    
    address public lendingPool;
    address public priceOracle;
    address public usdc;
    address public weth;
    address public wbtc;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("==============================================");
        console.log("   ARC LENDING PROTOCOL - DEPLOYMENT");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 1: Deploy Price Oracle
        // ═══════════════════════════════════════════════════════════════════
        console.log("Step 1: Deploying Price Oracle...");
        
        PriceOracle oracle = new PriceOracle();
        priceOracle = address(oracle);
        console.log("  PriceOracle deployed at:", priceOracle);
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 2: Deploy Test Tokens (for testnet)
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Step 2: Deploying Test Tokens...");
        
        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        usdc = address(mockUSDC);
        console.log("  Mock USDC deployed at:", usdc);
        
        // Deploy mock WETH
        MockERC20 mockWETH = new MockERC20("Wrapped Ether", "WETH", 18);
        weth = address(mockWETH);
        console.log("  Mock WETH deployed at:", weth);
        
        // Deploy mock WBTC
        MockERC20 mockWBTC = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        wbtc = address(mockWBTC);
        console.log("  Mock WBTC deployed at:", wbtc);
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 3: Deploy Lending Pool
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Step 3: Deploying Lending Pool...");
        
        ArcLendingPool pool = new ArcLendingPool(priceOracle);
        lendingPool = address(pool);
        console.log("  ArcLendingPool deployed at:", lendingPool);
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 4: Set Oracle Prices
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Step 4: Setting Oracle Prices...");
        
        // Prices in 18 decimals
        oracle.setPrice(usdc, 1e18);           // $1.00
        oracle.setPrice(weth, 3500e18);        // $3,500
        oracle.setPrice(wbtc, 95000e18);       // $95,000
        
        console.log("  USDC price: $1.00");
        console.log("  WETH price: $3,500");
        console.log("  WBTC price: $95,000");
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: List Markets
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Step 5: Listing Markets...");
        
        // List USDC market
        pool.listMarket(
            usdc,
            "Arc Lending USDC",
            "aUSDC",
            USDC_COLLATERAL_FACTOR,
            USDC_LIQUIDATION_THRESHOLD,
            USDC_RESERVE_FACTOR
        );
        console.log("  USDC market listed (85% LTV, 90% liquidation)");
        
        // List WETH market
        pool.listMarket(
            weth,
            "Arc Lending WETH",
            "aWETH",
            WETH_COLLATERAL_FACTOR,
            WETH_LIQUIDATION_THRESHOLD,
            WETH_RESERVE_FACTOR
        );
        console.log("  WETH market listed (75% LTV, 80% liquidation)");
        
        // List WBTC market
        pool.listMarket(
            wbtc,
            "Arc Lending WBTC",
            "aWBTC",
            WBTC_COLLATERAL_FACTOR,
            WBTC_LIQUIDATION_THRESHOLD,
            WBTC_RESERVE_FACTOR
        );
        console.log("  WBTC market listed (70% LTV, 75% liquidation)");
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 6: Mint Test Tokens to Deployer
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Step 6: Minting Test Tokens...");
        
        mockUSDC.mint(deployer, 1_000_000e6);    // 1M USDC
        mockWETH.mint(deployer, 1000e18);         // 1000 WETH
        mockWBTC.mint(deployer, 100e8);           // 100 WBTC
        
        console.log("  Minted 1,000,000 USDC to deployer");
        console.log("  Minted 1,000 WETH to deployer");
        console.log("  Minted 100 WBTC to deployer");
        
        vm.stopBroadcast();
        
        // ═══════════════════════════════════════════════════════════════════
        // DEPLOYMENT SUMMARY
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("==============================================");
        console.log("   DEPLOYMENT COMPLETE!");
        console.log("==============================================");
        console.log("");
        console.log("Contract Addresses:");
        console.log("-------------------");
        console.log("  PriceOracle:    ", priceOracle);
        console.log("  ArcLendingPool: ", lendingPool);
        console.log("  USDC:           ", usdc);
        console.log("  WETH:           ", weth);
        console.log("  WBTC:           ", wbtc);
        console.log("");
        console.log("Next Steps:");
        console.log("-----------");
        console.log("1. Verify contracts on Arcscan");
        console.log("2. Update frontend with contract addresses");
        console.log("3. Add initial liquidity to markets");
        console.log("4. Test supply, borrow, repay, and liquidation");
        console.log("");
        console.log("Verification Commands:");
        console.log("----------------------");
        console.log("forge verify-contract", priceOracle, "src/PriceOracle.sol:PriceOracle --chain-id 5042002");
        console.log("");
    }
}

/**
 * @title DeployLendingMainnet
 * @notice Production deployment with existing token addresses
 */
contract DeployLendingMainnet is Script {
    
    // Existing token addresses on Arc mainnet (update these)
    address constant USDC = address(0); // Add real address
    address constant WETH = address(0); // Add real address
    address constant WBTC = address(0); // Add real address
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy oracle
        PriceOracle oracle = new PriceOracle();
        
        // Deploy lending pool
        ArcLendingPool pool = new ArcLendingPool(address(oracle));
        
        // List markets with existing tokens
        // (Update with real addresses)
        
        vm.stopBroadcast();
    }
}
