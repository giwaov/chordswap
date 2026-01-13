// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ArcFactory.sol";
import "../src/ArcRouter.sol";
import "../src/ArcToken.sol";
import "../src/PerpExchange.sol";
import "../src/PriceOracle.sol";

/**
 * @title DeployArcDex
 * @dev Deployment script for the Arc DEX
 * 
 * Usage:
 * forge script script/Deploy.s.sol:DeployArcDex --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployArcDex is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Arc DEX contracts...");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Factory
        ArcFactory factory = new ArcFactory(deployer);
        console.log("ArcFactory deployed at:", address(factory));

        // Deploy Router
        ArcRouter router = new ArcRouter(address(factory));
        console.log("ArcRouter deployed at:", address(router));

        // Deploy test tokens for demonstration
        ArcToken tokenA = new ArcToken("Arc Token A", "ARCA", 18, 1_000_000);
        console.log("Token A (ARCA) deployed at:", address(tokenA));
        
        ArcToken tokenB = new ArcToken("Arc Token B", "ARCB", 18, 1_000_000);
        console.log("Token B (ARCB) deployed at:", address(tokenB));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
        console.log("Token A:", address(tokenA));
        console.log("Token B:", address(tokenB));
        console.log("\nSave these addresses in your .env file!");
    }
}

/**
 * @title CreatePair
 * @dev Script to create a new trading pair
 * 
 * Usage:
 * forge script script/Deploy.s.sol:CreatePair --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract CreatePair is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        address tokenA = vm.envAddress("TOKEN_A_ADDRESS");
        address tokenB = vm.envAddress("TOKEN_B_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ArcFactory factory = ArcFactory(factoryAddress);
        address pair = factory.createPair(tokenA, tokenB);
        
        console.log("Pair created at:", pair);
        
        vm.stopBroadcast();
    }
}

/**
 * @title AddLiquidity
 * @dev Script to add liquidity to a pair
 * 
 * Usage:
 * forge script script/Deploy.s.sol:AddLiquidity --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract AddLiquidity is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        address tokenA = vm.envAddress("TOKEN_A_ADDRESS");
        address tokenB = vm.envAddress("TOKEN_B_ADDRESS");
        
        uint256 amountA = 10000 * 1e18; // 10,000 tokens
        uint256 amountB = 10000 * 1e18; // 10,000 tokens
        
        vm.startBroadcast(deployerPrivateKey);
        
        ArcRouter router = ArcRouter(routerAddress);
        
        // Approve router to spend tokens
        ArcToken(tokenA).approve(routerAddress, amountA);
        ArcToken(tokenB).approve(routerAddress, amountB);
        
        // Add liquidity
        (uint256 actualA, uint256 actualB, uint256 liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0, // min amount A
            0, // min amount B
            msg.sender,
            block.timestamp + 300 // 5 min deadline
        );
        
        console.log("Liquidity added!");
        console.log("Amount A:", actualA);
        console.log("Amount B:", actualB);
        console.log("LP tokens:", liquidity);
        
        vm.stopBroadcast();
    }
}

/**
 * @title DeployPerpExchange
 * @dev Deployment script for the Perpetual DEX
 * 
 * Usage:
 * forge script script/Deploy.s.sol:DeployPerpExchange --rpc-url $ARC_TESTNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployPerpExchange is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Use Token A as collateral (or you can use a stablecoin)
        address collateralToken = vm.envAddress("TOKEN_A_ADDRESS");
        
        console.log("Deploying Perp Exchange contracts...");
        console.log("Deployer:", deployer);
        console.log("Collateral Token:", collateralToken);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Price Oracle
        PriceOracle priceOracle = new PriceOracle();
        console.log("PriceOracle deployed at:", address(priceOracle));

        // Deploy Perp Exchange
        PerpExchange perpExchange = new PerpExchange(collateralToken, address(priceOracle));
        console.log("PerpExchange deployed at:", address(perpExchange));

        // Add Token B as a tradeable market
        address tokenB = vm.envAddress("TOKEN_B_ADDRESS");
        perpExchange.addMarket(tokenB);
        console.log("Added market for Token B:", tokenB);
        
        // Set initial price for Token B (1 USD = 1e18)
        priceOracle.setPrice(tokenB, 1e18);
        console.log("Set initial price for Token B: $1.00");

        vm.stopBroadcast();

        console.log("\n=== Perp Exchange Deployment Summary ===");
        console.log("Price Oracle:", address(priceOracle));
        console.log("Perp Exchange:", address(perpExchange));
        console.log("Collateral Token:", collateralToken);
        console.log("Tradeable Market:", tokenB);
        console.log("\nSave these addresses in your .env file!");
    }
}

/**
 * @title SetupPerpMarket
 * @dev Script to add a new market to the Perp Exchange
 */
contract SetupPerpMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address perpExchangeAddress = vm.envAddress("PERP_EXCHANGE_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address tokenAddress = vm.envAddress("NEW_MARKET_TOKEN");
        uint256 initialPrice = vm.envUint("INITIAL_PRICE"); // in wei (1e18 = $1)
        
        vm.startBroadcast(deployerPrivateKey);
        
        PerpExchange perp = PerpExchange(perpExchangeAddress);
        PriceOracle oracle = PriceOracle(oracleAddress);
        
        // Add market
        perp.addMarket(tokenAddress);
        console.log("Added market:", tokenAddress);
        
        // Set initial price
        oracle.setPrice(tokenAddress, initialPrice);
        console.log("Set price:", initialPrice);
        
        vm.stopBroadcast();
    }
}

/**
 * @title UpdatePrice
 * @dev Script to update token price in oracle
 */
contract UpdatePrice is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 newPrice = vm.envUint("NEW_PRICE"); // in wei (1e18 = $1)
        
        vm.startBroadcast(deployerPrivateKey);
        
        PriceOracle oracle = PriceOracle(oracleAddress);
        oracle.setPrice(tokenAddress, newPrice);
        console.log("Updated price for", tokenAddress, "to", newPrice);
        
        vm.stopBroadcast();
    }
}
