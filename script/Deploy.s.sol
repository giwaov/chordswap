// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ArcFactory.sol";
import "../src/ArcRouter.sol";
import "../src/ArcToken.sol";

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
