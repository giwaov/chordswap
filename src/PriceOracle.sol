// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @notice Simple price oracle for perpetual exchange
 * @dev In production, use Chainlink or other decentralized oracle
 */
contract PriceOracle is Ownable {
    // Token => Price in USD (18 decimals)
    mapping(address => uint256) public prices;
    
    // Token => Last update timestamp
    mapping(address => uint256) public lastUpdated;
    
    // Authorized price updaters
    mapping(address => bool) public updaters;
    
    // Events
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event UpdaterSet(address indexed updater, bool authorized);

    constructor() Ownable(msg.sender) {
        updaters[msg.sender] = true;
    }

    modifier onlyUpdater() {
        require(updaters[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    /**
     * @notice Set price for a token
     * @param token The token address
     * @param price The price in USD with 18 decimals (e.g., 1 USD = 1e18)
     */
    function setPrice(address token, uint256 price) external onlyUpdater {
        require(price > 0, "Invalid price");
        prices[token] = price;
        lastUpdated[token] = block.timestamp;
        emit PriceUpdated(token, price, block.timestamp);
    }

    /**
     * @notice Batch set prices for multiple tokens
     * @param tokens Array of token addresses
     * @param _prices Array of prices
     */
    function setPrices(address[] calldata tokens, uint256[] calldata _prices) external onlyUpdater {
        require(tokens.length == _prices.length, "Length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            require(_prices[i] > 0, "Invalid price");
            prices[tokens[i]] = _prices[i];
            lastUpdated[tokens[i]] = block.timestamp;
            emit PriceUpdated(tokens[i], _prices[i], block.timestamp);
        }
    }

    /**
     * @notice Get the price of a token
     * @param token The token address
     * @return The price in USD with 18 decimals
     */
    function getPrice(address token) external view returns (uint256) {
        uint256 price = prices[token];
        require(price > 0, "Price not set");
        return price;
    }

    /**
     * @notice Get price with staleness check
     * @param token The token address
     * @param maxAge Maximum age in seconds
     * @return price The price
     * @return timestamp Last update time
     */
    function getPriceWithAge(address token, uint256 maxAge) external view returns (uint256 price, uint256 timestamp) {
        price = prices[token];
        timestamp = lastUpdated[token];
        require(price > 0, "Price not set");
        require(block.timestamp - timestamp <= maxAge, "Price stale");
    }

    /**
     * @notice Set or revoke updater authorization
     * @param updater The address to authorize/revoke
     * @param authorized True to authorize, false to revoke
     */
    function setUpdater(address updater, bool authorized) external onlyOwner {
        updaters[updater] = authorized;
        emit UpdaterSet(updater, authorized);
    }
}
