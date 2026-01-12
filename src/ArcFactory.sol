// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ArcPair.sol";

/**
 * @title ArcFactory
 * @dev Factory contract for creating and managing AMM trading pairs on Arc Testnet
 */
contract ArcFactory {
    // Fee recipient address
    address public feeTo;
    address public feeToSetter;

    // Mapping of token pairs to pair addresses
    mapping(address => mapping(address => address)) public getPair;
    
    // Array of all pairs
    address[] public allPairs;

    // Events
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    /**
     * @dev Returns the number of pairs created
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @dev Create a new trading pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Address of the created pair
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "ArcFactory: identical addresses");
        
        // Sort tokens to ensure consistent ordering
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        require(token0 != address(0), "ArcFactory: zero address");
        require(getPair[token0][token1] == address(0), "ArcFactory: pair exists");

        // Create new pair using CREATE2 for deterministic addresses
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        ArcPair newPair = new ArcPair{salt: salt}(token0, token1);
        pair = address(newPair);

        // Store pair in mappings (both directions)
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     * @dev Set fee recipient
     */
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "ArcFactory: forbidden");
        feeTo = _feeTo;
    }

    /**
     * @dev Set fee setter address
     */
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "ArcFactory: forbidden");
        feeToSetter = _feeToSetter;
    }

    /**
     * @dev Get pair address for two tokens (with sorting)
     */
    function getPairAddress(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return getPair[token0][token1];
    }

    /**
     * @dev Get all pairs
     */
    function getAllPairs() external view returns (address[] memory) {
        return allPairs;
    }
}
