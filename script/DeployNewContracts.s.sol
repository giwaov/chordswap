// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LimitOrderBook.sol";
import "../src/LPFarm.sol";

/**
 * @title DeployNewContracts
 * @dev Deployment script for LimitOrderBook and LPFarm
 * 
 * Usage:
 * forge script script/DeployNewContracts.s.sol:DeployNewContracts --rpc-url https://rpc.testnet.arc.network --broadcast -vvvv
 */
contract DeployNewContracts is Script {
    // Existing deployed contracts
    address constant ROUTER = 0x4e739222ef41B7f6452058cDA9a2b1d41F4fc04B;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying new contracts...");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy LimitOrderBook
        LimitOrderBook limitOrderBook = new LimitOrderBook(ROUTER);
        console.log("LimitOrderBook deployed at:", address(limitOrderBook));

        // Deploy ChordToken first
        ChordToken chordToken = new ChordToken();
        console.log("ChordToken deployed at:", address(chordToken));

        // Deploy LPFarm with ChordToken, 1 CHORD per second reward, starting now
        LPFarm lpFarm = new LPFarm(
            address(chordToken),
            1 ether, // 1 CHORD per second
            block.timestamp
        );
        console.log("LPFarm deployed at:", address(lpFarm));
        
        // Set LPFarm as minter for ChordToken
        chordToken.setMinter(address(lpFarm), true);
        console.log("LPFarm set as minter for ChordToken");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("LimitOrderBook:", address(limitOrderBook));
        console.log("ChordToken:", address(chordToken));
        console.log("LPFarm:", address(lpFarm));
        console.log("\nUpdate these addresses in frontend/src/config.ts!");
    }
}
