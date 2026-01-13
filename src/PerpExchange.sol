// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

/**
 * @title PerpExchange
 * @notice Perpetual futures exchange with leverage trading
 * @dev Supports long/short positions with up to 50x leverage
 */
contract PerpExchange is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_LEVERAGE = 50;
    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80% = position liquidated when margin < 20% of required
    uint256 public constant LIQUIDATION_BONUS = 5; // 5% bonus for liquidators
    uint256 public constant FUNDING_INTERVAL = 8 hours;
    uint256 public constant TRADING_FEE = 10; // 0.1% = 10 basis points

    // State
    IPriceOracle public priceOracle;
    IERC20 public collateralToken; // USDC or similar stablecoin
    
    uint256 public totalLongOpenInterest;
    uint256 public totalShortOpenInterest;
    uint256 public lastFundingTime;
    int256 public cumulativeFundingRate;
    
    // Position tracking
    struct Position {
        uint256 size;           // Position size in tokens
        uint256 collateral;     // Collateral amount
        uint256 entryPrice;     // Entry price
        int256 entryFundingRate; // Funding rate at entry
        bool isLong;            // Long or short
        uint256 lastUpdateTime; // Last position update
    }
    
    // User positions: user => token => position
    mapping(address => mapping(address => Position)) public positions;
    
    // Supported markets
    mapping(address => bool) public supportedMarkets;
    address[] public marketList;
    
    // Events
    event PositionOpened(
        address indexed user,
        address indexed token,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint256 leverage
    );
    
    event PositionClosed(
        address indexed user,
        address indexed token,
        bool isLong,
        uint256 size,
        uint256 collateral,
        int256 pnl
    );
    
    event PositionLiquidated(
        address indexed user,
        address indexed token,
        address indexed liquidator,
        uint256 size,
        uint256 collateral
    );
    
    event CollateralAdded(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    
    event CollateralRemoved(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    
    event MarketAdded(address indexed token);
    event FundingUpdated(int256 fundingRate, uint256 timestamp);

    constructor(address _collateralToken, address _priceOracle) Ownable(msg.sender) {
        collateralToken = IERC20(_collateralToken);
        priceOracle = IPriceOracle(_priceOracle);
        lastFundingTime = block.timestamp;
    }

    // ============ Admin Functions ============

    function addMarket(address token) external onlyOwner {
        require(!supportedMarkets[token], "Market exists");
        supportedMarkets[token] = true;
        marketList.push(token);
        emit MarketAdded(token);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IPriceOracle(_priceOracle);
    }

    // ============ Trading Functions ============

    /**
     * @notice Open a leveraged position
     * @param token The token to trade
     * @param collateralAmount Amount of collateral to deposit
     * @param leverage Leverage multiplier (1-50)
     * @param isLong True for long, false for short
     */
    function openPosition(
        address token,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external nonReentrant {
        require(supportedMarkets[token], "Market not supported");
        require(leverage >= 1 && leverage <= MAX_LEVERAGE, "Invalid leverage");
        require(collateralAmount > 0, "Zero collateral");
        
        Position storage position = positions[msg.sender][token];
        require(position.size == 0, "Position exists, close first");
        
        // Update funding before position change
        _updateFunding();
        
        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Get current price
        uint256 currentPrice = priceOracle.getPrice(token);
        require(currentPrice > 0, "Invalid price");
        
        // Calculate position size (in token units)
        uint256 positionValue = collateralAmount * leverage;
        uint256 size = (positionValue * PRECISION) / currentPrice;
        
        // Deduct trading fee
        uint256 fee = (collateralAmount * TRADING_FEE) / 10000;
        uint256 netCollateral = collateralAmount - fee;
        
        // Create position
        position.size = size;
        position.collateral = netCollateral;
        position.entryPrice = currentPrice;
        position.entryFundingRate = cumulativeFundingRate;
        position.isLong = isLong;
        position.lastUpdateTime = block.timestamp;
        
        // Update open interest
        if (isLong) {
            totalLongOpenInterest += positionValue;
        } else {
            totalShortOpenInterest += positionValue;
        }
        
        emit PositionOpened(
            msg.sender,
            token,
            isLong,
            size,
            netCollateral,
            currentPrice,
            leverage
        );
    }

    /**
     * @notice Close an existing position
     * @param token The token market to close
     */
    function closePosition(address token) external nonReentrant {
        Position storage position = positions[msg.sender][token];
        require(position.size > 0, "No position");
        
        // Update funding
        _updateFunding();
        
        // Calculate PnL
        (int256 pnl, int256 fundingFee) = _calculatePnL(msg.sender, token);
        
        // Calculate final collateral
        int256 finalCollateral = int256(position.collateral) + pnl - fundingFee;
        
        // Deduct closing fee
        uint256 currentPrice = priceOracle.getPrice(token);
        uint256 positionValue = (position.size * currentPrice) / PRECISION;
        uint256 closingFee = (positionValue * TRADING_FEE) / 10000;
        finalCollateral -= int256(closingFee);
        
        // Update open interest
        uint256 entryValue = (position.size * position.entryPrice) / PRECISION;
        if (position.isLong) {
            totalLongOpenInterest = totalLongOpenInterest > entryValue ? 
                totalLongOpenInterest - entryValue : 0;
        } else {
            totalShortOpenInterest = totalShortOpenInterest > entryValue ? 
                totalShortOpenInterest - entryValue : 0;
        }
        
        // Clear position
        uint256 size = position.size;
        uint256 collateral = position.collateral;
        bool isLong = position.isLong;
        delete positions[msg.sender][token];
        
        // Transfer remaining collateral
        if (finalCollateral > 0) {
            collateralToken.safeTransfer(msg.sender, uint256(finalCollateral));
        }
        
        emit PositionClosed(msg.sender, token, isLong, size, collateral, pnl);
    }

    /**
     * @notice Add collateral to an existing position
     * @param token The token market
     * @param amount Amount of collateral to add
     */
    function addCollateral(address token, uint256 amount) external nonReentrant {
        Position storage position = positions[msg.sender][token];
        require(position.size > 0, "No position");
        require(amount > 0, "Zero amount");
        
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        position.collateral += amount;
        
        emit CollateralAdded(msg.sender, token, amount);
    }

    /**
     * @notice Remove collateral from a position (if healthy)
     * @param token The token market
     * @param amount Amount to remove
     */
    function removeCollateral(address token, uint256 amount) external nonReentrant {
        Position storage position = positions[msg.sender][token];
        require(position.size > 0, "No position");
        require(amount > 0 && amount < position.collateral, "Invalid amount");
        
        // Check if position remains healthy after removal
        uint256 newCollateral = position.collateral - amount;
        uint256 currentPrice = priceOracle.getPrice(token);
        uint256 positionValue = (position.size * currentPrice) / PRECISION;
        
        // Minimum 5% margin required
        require(newCollateral >= positionValue / 20, "Insufficient margin");
        
        position.collateral = newCollateral;
        collateralToken.safeTransfer(msg.sender, amount);
        
        emit CollateralRemoved(msg.sender, token, amount);
    }

    /**
     * @notice Liquidate an unhealthy position
     * @param user The user to liquidate
     * @param token The token market
     */
    function liquidate(address user, address token) external nonReentrant {
        Position storage position = positions[user][token];
        require(position.size > 0, "No position");
        require(_isLiquidatable(user, token), "Not liquidatable");
        
        // Update funding
        _updateFunding();
        
        // Calculate remaining collateral
        (int256 pnl, int256 fundingFee) = _calculatePnL(user, token);
        int256 remainingCollateral = int256(position.collateral) + pnl - fundingFee;
        
        // Liquidator bonus (5% of collateral)
        uint256 liquidatorBonus = (position.collateral * LIQUIDATION_BONUS) / 100;
        
        // Update open interest
        uint256 entryValue = (position.size * position.entryPrice) / PRECISION;
        if (position.isLong) {
            totalLongOpenInterest = totalLongOpenInterest > entryValue ? 
                totalLongOpenInterest - entryValue : 0;
        } else {
            totalShortOpenInterest = totalShortOpenInterest > entryValue ? 
                totalShortOpenInterest - entryValue : 0;
        }
        
        // Clear position
        uint256 size = position.size;
        uint256 collateral = position.collateral;
        delete positions[user][token];
        
        // Pay liquidator
        if (remainingCollateral > int256(liquidatorBonus)) {
            collateralToken.safeTransfer(msg.sender, liquidatorBonus);
        } else if (remainingCollateral > 0) {
            collateralToken.safeTransfer(msg.sender, uint256(remainingCollateral));
        }
        
        emit PositionLiquidated(user, token, msg.sender, size, collateral);
    }

    // ============ View Functions ============

    /**
     * @notice Get position details for a user
     */
    function getPosition(address user, address token) external view returns (
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        bool isLong,
        int256 unrealizedPnl,
        uint256 leverage,
        uint256 liquidationPrice
    ) {
        Position memory position = positions[user][token];
        if (position.size == 0) {
            return (0, 0, 0, false, 0, 0, 0);
        }
        
        size = position.size;
        collateral = position.collateral;
        entryPrice = position.entryPrice;
        isLong = position.isLong;
        
        (unrealizedPnl,) = _calculatePnL(user, token);
        
        uint256 positionValue = (size * entryPrice) / PRECISION;
        leverage = positionValue / collateral;
        
        liquidationPrice = _calculateLiquidationPrice(user, token);
    }

    /**
     * @notice Check if a position can be liquidated
     */
    function isLiquidatable(address user, address token) external view returns (bool) {
        return _isLiquidatable(user, token);
    }

    /**
     * @notice Get all supported markets
     */
    function getMarkets() external view returns (address[] memory) {
        return marketList;
    }

    /**
     * @notice Get funding rate info
     */
    function getFundingInfo() external view returns (
        int256 currentFundingRate,
        uint256 nextFundingTime,
        uint256 longOI,
        uint256 shortOI
    ) {
        currentFundingRate = _calculateCurrentFundingRate();
        nextFundingTime = lastFundingTime + FUNDING_INTERVAL;
        longOI = totalLongOpenInterest;
        shortOI = totalShortOpenInterest;
    }

    // ============ Internal Functions ============

    function _calculatePnL(address user, address token) internal view returns (int256 pnl, int256 fundingFee) {
        Position memory position = positions[user][token];
        if (position.size == 0) return (0, 0);
        
        uint256 currentPrice = priceOracle.getPrice(token);
        
        // Calculate price PnL
        if (position.isLong) {
            // Long: profit when price goes up
            pnl = int256((position.size * currentPrice) / PRECISION) - 
                  int256((position.size * position.entryPrice) / PRECISION);
        } else {
            // Short: profit when price goes down
            pnl = int256((position.size * position.entryPrice) / PRECISION) - 
                  int256((position.size * currentPrice) / PRECISION);
        }
        
        // Calculate funding fee
        int256 fundingDelta = cumulativeFundingRate - position.entryFundingRate;
        int256 positionValue = int256((position.size * position.entryPrice) / PRECISION);
        
        if (position.isLong) {
            fundingFee = (positionValue * fundingDelta) / int256(PRECISION);
        } else {
            fundingFee = -(positionValue * fundingDelta) / int256(PRECISION);
        }
    }

    function _isLiquidatable(address user, address token) internal view returns (bool) {
        Position memory position = positions[user][token];
        if (position.size == 0) return false;
        
        (int256 pnl, int256 fundingFee) = _calculatePnL(user, token);
        int256 currentMargin = int256(position.collateral) + pnl - fundingFee;
        
        // Position value at current price
        uint256 currentPrice = priceOracle.getPrice(token);
        uint256 positionValue = (position.size * currentPrice) / PRECISION;
        
        // Required margin is 1/leverage of position value (min 2%)
        uint256 requiredMargin = positionValue / 50; // 2% minimum
        
        // Liquidate if margin falls below threshold
        return currentMargin < int256((requiredMargin * LIQUIDATION_THRESHOLD) / 100);
    }

    function _calculateLiquidationPrice(address user, address token) internal view returns (uint256) {
        Position memory position = positions[user][token];
        if (position.size == 0) return 0;
        
        // Simplified liquidation price calculation
        // When margin = 2% of position value, position is liquidatable
        uint256 collateral = position.collateral;
        uint256 size = position.size;
        uint256 entryPrice = position.entryPrice;
        
        if (position.isLong) {
            // Liq price = entry - (collateral * 0.98) / size * PRECISION
            uint256 maxLoss = (collateral * 98) / 100;
            if ((maxLoss * PRECISION) / size >= entryPrice) return 0;
            return entryPrice - ((maxLoss * PRECISION) / size);
        } else {
            // Liq price = entry + (collateral * 0.98) / size * PRECISION
            uint256 maxLoss = (collateral * 98) / 100;
            return entryPrice + ((maxLoss * PRECISION) / size);
        }
    }

    function _calculateCurrentFundingRate() internal view returns (int256) {
        if (totalLongOpenInterest == 0 && totalShortOpenInterest == 0) return 0;
        
        // Funding rate based on OI imbalance
        // Positive = longs pay shorts, Negative = shorts pay longs
        int256 imbalance = int256(totalLongOpenInterest) - int256(totalShortOpenInterest);
        int256 totalOI = int256(totalLongOpenInterest + totalShortOpenInterest);
        
        if (totalOI == 0) return 0;
        
        // Rate = imbalance / totalOI * 0.01% per hour
        return (imbalance * int256(PRECISION) * 1) / (totalOI * 10000);
    }

    function _updateFunding() internal {
        if (block.timestamp < lastFundingTime + FUNDING_INTERVAL) return;
        
        uint256 periods = (block.timestamp - lastFundingTime) / FUNDING_INTERVAL;
        int256 fundingRate = _calculateCurrentFundingRate();
        
        cumulativeFundingRate += fundingRate * int256(periods);
        lastFundingTime = block.timestamp;
        
        emit FundingUpdated(fundingRate, block.timestamp);
    }
}
