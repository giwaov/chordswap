// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./InterestRateModel.sol";
import "./ArcLendToken.sol";

/**
 * @title ArcLendingPool
 * @author ChordSwap
 * @notice World-class lending protocol for Arc Network
 * @dev Full-featured lending pool with supply, borrow, repay, liquidation, and flash loans
 * 
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                         ARC LENDING PROTOCOL                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║  Features:                                                                 ║
 * ║  • Multi-asset lending with isolated risk                                  ║
 * ║  • Dynamic interest rates based on utilization                             ║
 * ║  • Overcollateralized borrowing with health factor                         ║
 * ║  • Liquidation mechanism with bonus incentives                             ║
 * ║  • Flash loans for arbitrage and liquidations                              ║
 * ║  • Interest-bearing aTokens (rebasing)                                     ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
contract ArcLendingPool is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // 1.0
    uint256 public constant LIQUIDATION_BONUS = 5e16; // 5% bonus
    uint256 public constant LIQUIDATION_CLOSE_FACTOR = 50e16; // 50% max
    uint256 public constant FLASH_LOAN_FEE = 9e14; // 0.09%
    uint256 public constant MAX_RESERVE_FACTOR = 50e16; // 50% max
    
    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Configuration for each asset market
    struct Market {
        ArcLendToken aToken;           // Interest-bearing token
        uint256 collateralFactor;      // LTV ratio (1e18 = 100%)
        uint256 liquidationThreshold;  // Liquidation LTV (1e18 = 100%)
        uint256 reserveFactor;         // Protocol fee (1e18 = 100%)
        uint256 totalSupply;           // Total underlying supplied
        uint256 totalBorrows;          // Total borrowed
        uint256 totalReserves;         // Protocol reserves
        uint256 borrowIndex;           // Cumulative borrow interest
        uint256 lastUpdateTime;        // Last accrual timestamp
        bool isListed;                 // Market is active
        bool canBorrow;                // Borrowing enabled
        bool canCollateral;            // Can be used as collateral
    }
    
    /// @notice User's borrow position per asset
    struct BorrowSnapshot {
        uint256 principal;      // Original borrow amount
        uint256 borrowIndex;    // Index at time of borrow
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Interest rate model
    InterestRateModel public interestRateModel;
    
    /// @notice Price oracle for asset prices
    address public priceOracle;
    
    /// @notice All listed markets
    address[] public allMarkets;
    
    /// @notice Market data for each asset
    mapping(address => Market) public markets;
    
    /// @notice User borrow data: user => asset => snapshot
    mapping(address => mapping(address => BorrowSnapshot)) public borrowSnapshots;
    
    /// @notice Assets user is using as collateral
    mapping(address => mapping(address => bool)) public userCollateral;
    
    /// @notice Assets user has borrowed
    mapping(address => address[]) public userBorrowedAssets;
    
    /// @notice Assets user is supplying as collateral
    mapping(address => address[]) public userCollateralAssets;
    
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════
    
    event MarketListed(address indexed asset, address indexed aToken);
    event Supply(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);
    event Borrow(address indexed user, address indexed asset, uint256 amount);
    event Repay(address indexed user, address indexed asset, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        address indexed repayAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint256 seizedAmount
    );
    event FlashLoan(
        address indexed receiver,
        address indexed asset,
        uint256 amount,
        uint256 fee
    );
    event CollateralEnabled(address indexed user, address indexed asset);
    event CollateralDisabled(address indexed user, address indexed asset);
    event InterestAccrued(address indexed asset, uint256 interestAccumulated, uint256 newBorrowIndex);
    event ReservesUpdated(address indexed asset, uint256 newReserves);
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    
    error MarketNotListed();
    error MarketAlreadyListed();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error HealthFactorOk();
    error HealthFactorBroken();
    error InvalidAmount();
    error InvalidAddress();
    error BorrowNotAllowed();
    error RepayTooMuch();
    error LiquidateTooMuch();
    error FlashLoanFailed();
    error SameAsset();
    error CollateralNotEnabled();
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════
    
    constructor(address _priceOracle) Ownable(msg.sender) {
        if (_priceOracle == address(0)) revert InvalidAddress();
        priceOracle = _priceOracle;
        interestRateModel = new InterestRateModel();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice List a new market
     * @param asset The underlying asset
     * @param aTokenName Name for the aToken
     * @param aTokenSymbol Symbol for the aToken
     * @param collateralFactor LTV ratio (e.g., 75e16 = 75%)
     * @param liquidationThreshold Liquidation LTV (e.g., 80e16 = 80%)
     * @param reserveFactor Protocol fee (e.g., 10e16 = 10%)
     */
    function listMarket(
        address asset,
        string calldata aTokenName,
        string calldata aTokenSymbol,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 reserveFactor
    ) external onlyOwner {
        if (asset == address(0)) revert InvalidAddress();
        if (markets[asset].isListed) revert MarketAlreadyListed();
        if (collateralFactor > liquidationThreshold) revert InvalidAmount();
        if (reserveFactor > MAX_RESERVE_FACTOR) revert InvalidAmount();
        
        // Create aToken
        ArcLendToken aToken = new ArcLendToken(aTokenName, aTokenSymbol, IERC20(asset));
        aToken.setLendingPool(address(this));
        
        markets[asset] = Market({
            aToken: aToken,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            reserveFactor: reserveFactor,
            totalSupply: 0,
            totalBorrows: 0,
            totalReserves: 0,
            borrowIndex: PRECISION,
            lastUpdateTime: block.timestamp,
            isListed: true,
            canBorrow: true,
            canCollateral: true
        });
        
        allMarkets.push(asset);
        
        emit MarketListed(asset, address(aToken));
    }
    
    /**
     * @notice Update market parameters
     */
    function updateMarket(
        address asset,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 reserveFactor,
        bool canBorrow,
        bool canCollateral
    ) external onlyOwner {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        
        market.collateralFactor = collateralFactor;
        market.liquidationThreshold = liquidationThreshold;
        market.reserveFactor = reserveFactor;
        market.canBorrow = canBorrow;
        market.canCollateral = canCollateral;
    }
    
    /**
     * @notice Set price oracle
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) revert InvalidAddress();
        priceOracle = _priceOracle;
    }
    
    /**
     * @notice Withdraw reserves
     */
    function withdrawReserves(address asset, uint256 amount, address to) external onlyOwner {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        if (amount > market.totalReserves) revert InvalidAmount();
        
        market.totalReserves -= amount;
        IERC20(asset).safeTransfer(to, amount);
    }
    
    /**
     * @notice Pause/unpause protocol
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SUPPLY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Supply assets to earn interest
     * @param asset The asset to supply
     * @param amount Amount to supply
     */
    function supply(address asset, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        
        // Accrue interest first
        _accrueInterest(asset);
        
        // Transfer underlying from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Mint aTokens
        uint256 totalUnderlying = market.totalSupply;
        market.aToken.mint(msg.sender, amount, totalUnderlying);
        
        // Update state
        market.totalSupply += amount;
        
        emit Supply(msg.sender, asset, amount);
    }
    
    /**
     * @notice Withdraw supplied assets
     * @param asset The asset to withdraw
     * @param amount Amount to withdraw (use type(uint256).max for all)
     */
    function withdraw(address asset, uint256 amount) external nonReentrant whenNotPaused {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        
        // Accrue interest first
        _accrueInterest(asset);
        
        // Calculate actual amount to withdraw
        uint256 userShares = market.aToken.balanceOf(msg.sender);
        uint256 maxWithdraw = market.aToken.sharesToUnderlying(userShares, market.totalSupply);
        
        if (amount == type(uint256).max) {
            amount = maxWithdraw;
        }
        
        if (amount > maxWithdraw) revert InvalidAmount();
        
        // Check liquidity
        uint256 available = market.totalSupply - market.totalBorrows;
        if (amount > available) revert InsufficientLiquidity();
        
        // Burn aTokens
        market.aToken.burnAmount(msg.sender, amount, market.totalSupply);
        
        // Update state
        market.totalSupply -= amount;
        
        // Check health factor if using as collateral
        if (userCollateral[msg.sender][asset]) {
            if (_healthFactor(msg.sender) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
                revert InsufficientCollateral();
            }
        }
        
        // Transfer underlying to user
        IERC20(asset).safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, asset, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // COLLATERAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Enable an asset as collateral
     * @param asset The asset to enable
     */
    function enableCollateral(address asset) external {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        if (!market.canCollateral) revert CollateralNotEnabled();
        
        if (!userCollateral[msg.sender][asset]) {
            userCollateral[msg.sender][asset] = true;
            userCollateralAssets[msg.sender].push(asset);
            emit CollateralEnabled(msg.sender, asset);
        }
    }
    
    /**
     * @notice Disable an asset as collateral
     * @param asset The asset to disable
     */
    function disableCollateral(address asset) external {
        if (userCollateral[msg.sender][asset]) {
            userCollateral[msg.sender][asset] = false;
            
            // Remove from array
            address[] storage assets = userCollateralAssets[msg.sender];
            for (uint256 i = 0; i < assets.length; i++) {
                if (assets[i] == asset) {
                    assets[i] = assets[assets.length - 1];
                    assets.pop();
                    break;
                }
            }
            
            // Check health factor
            if (_healthFactor(msg.sender) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
                revert InsufficientCollateral();
            }
            
            emit CollateralDisabled(msg.sender, asset);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BORROW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Borrow assets against collateral
     * @param asset The asset to borrow
     * @param amount Amount to borrow
     */
    function borrow(address asset, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        if (!market.canBorrow) revert BorrowNotAllowed();
        
        // Accrue interest first
        _accrueInterest(asset);
        
        // Check liquidity
        uint256 available = market.totalSupply - market.totalBorrows;
        if (amount > available) revert InsufficientLiquidity();
        
        // Update user borrow
        BorrowSnapshot storage snapshot = borrowSnapshots[msg.sender][asset];
        
        // Add to borrowed assets list if first borrow
        if (snapshot.principal == 0) {
            userBorrowedAssets[msg.sender].push(asset);
        }
        
        // Calculate current borrow balance with interest
        uint256 currentBorrow = _borrowBalance(msg.sender, asset);
        
        // Update snapshot
        snapshot.principal = currentBorrow + amount;
        snapshot.borrowIndex = market.borrowIndex;
        
        // Update market
        market.totalBorrows += amount;
        
        // Check health factor
        if (_healthFactor(msg.sender) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            revert InsufficientCollateral();
        }
        
        // Transfer to user
        IERC20(asset).safeTransfer(msg.sender, amount);
        
        emit Borrow(msg.sender, asset, amount);
    }
    
    /**
     * @notice Repay borrowed assets
     * @param asset The asset to repay
     * @param amount Amount to repay (use type(uint256).max for all)
     */
    function repay(address asset, uint256 amount) external nonReentrant whenNotPaused {
        _repayInternal(msg.sender, msg.sender, asset, amount);
    }
    
    /**
     * @notice Repay on behalf of another user
     */
    function repayBehalf(
        address borrower,
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        _repayInternal(msg.sender, borrower, asset, amount);
    }
    
    function _repayInternal(
        address payer,
        address borrower,
        address asset,
        uint256 amount
    ) internal {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        
        // Accrue interest first
        _accrueInterest(asset);
        
        // Get current borrow balance
        uint256 currentBorrow = _borrowBalance(borrower, asset);
        if (currentBorrow == 0) revert InvalidAmount();
        
        // Calculate repay amount
        uint256 repayAmount = amount == type(uint256).max ? currentBorrow : amount;
        if (repayAmount > currentBorrow) revert RepayTooMuch();
        
        // Transfer from payer
        IERC20(asset).safeTransferFrom(payer, address(this), repayAmount);
        
        // Update snapshot
        BorrowSnapshot storage snapshot = borrowSnapshots[borrower][asset];
        snapshot.principal = currentBorrow - repayAmount;
        snapshot.borrowIndex = market.borrowIndex;
        
        // Update market
        market.totalBorrows -= repayAmount;
        
        // Remove from borrowed assets if fully repaid
        if (snapshot.principal == 0) {
            _removeFromBorrowedAssets(borrower, asset);
        }
        
        emit Repay(borrower, asset, repayAmount);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDATION
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Liquidate an undercollateralized position
     * @param borrower The borrower to liquidate
     * @param repayAsset The asset to repay
     * @param collateralAsset The collateral to seize
     * @param repayAmount Amount to repay
     */
    function liquidate(
        address borrower,
        address repayAsset,
        address collateralAsset,
        uint256 repayAmount
    ) external nonReentrant whenNotPaused {
        if (borrower == msg.sender) revert InvalidAddress();
        if (repayAsset == collateralAsset) revert SameAsset();
        
        Market storage repayMarket = markets[repayAsset];
        Market storage collateralMarket = markets[collateralAsset];
        
        if (!repayMarket.isListed || !collateralMarket.isListed) revert MarketNotListed();
        
        // Accrue interest
        _accrueInterest(repayAsset);
        _accrueInterest(collateralAsset);
        
        // Check if liquidatable
        if (_healthFactor(borrower) >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            revert HealthFactorOk();
        }
        
        // Calculate max repay (close factor)
        uint256 currentBorrowBalance = _borrowBalance(borrower, repayAsset);
        uint256 maxRepay = (currentBorrowBalance * LIQUIDATION_CLOSE_FACTOR) / PRECISION;
        
        if (repayAmount > maxRepay) revert LiquidateTooMuch();
        
        // Calculate collateral to seize
        uint256 repayValue = _getAssetValue(repayAsset, repayAmount);
        uint256 seizeValue = (repayValue * (PRECISION + LIQUIDATION_BONUS)) / PRECISION;
        uint256 seizeAmount = _getAssetAmount(collateralAsset, seizeValue);
        
        // Check borrower has enough collateral
        uint256 borrowerCollateral = _userAssetBalance(borrower, collateralAsset);
        if (seizeAmount > borrowerCollateral) {
            seizeAmount = borrowerCollateral;
        }
        
        // Execute liquidation
        
        // 1. Repay debt
        IERC20(repayAsset).safeTransferFrom(msg.sender, address(this), repayAmount);
        
        BorrowSnapshot storage snapshot = borrowSnapshots[borrower][repayAsset];
        snapshot.principal = currentBorrowBalance - repayAmount;
        snapshot.borrowIndex = repayMarket.borrowIndex;
        repayMarket.totalBorrows -= repayAmount;
        
        // 2. Seize collateral (transfer aTokens)
        collateralMarket.aToken.transferFrom(borrower, msg.sender, 
            collateralMarket.aToken.underlyingToShares(seizeAmount, collateralMarket.totalSupply));
        
        emit Liquidate(msg.sender, borrower, repayAsset, collateralAsset, repayAmount, seizeAmount);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FLASH LOANS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Execute a flash loan
     * @param asset The asset to borrow
     * @param amount Amount to borrow
     * @param receiver The contract receiving the loan
     * @param data Arbitrary data to pass to receiver
     */
    function flashLoan(
        address asset,
        uint256 amount,
        address receiver,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        Market storage market = markets[asset];
        if (!market.isListed) revert MarketNotListed();
        
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        if (amount > balanceBefore) revert InsufficientLiquidity();
        
        // Calculate fee
        uint256 fee = (amount * FLASH_LOAN_FEE) / PRECISION;
        
        // Transfer to receiver
        IERC20(asset).safeTransfer(receiver, amount);
        
        // Call receiver
        IFlashLoanReceiver(receiver).executeOperation(asset, amount, fee, msg.sender, data);
        
        // Check repayment
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert FlashLoanFailed();
        
        // Add fee to reserves
        market.totalReserves += fee;
        
        emit FlashLoan(receiver, asset, amount, fee);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INTEREST ACCRUAL
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Accrue interest for a market
     */
    function accrueInterest(address asset) external {
        _accrueInterest(asset);
    }
    
    function _accrueInterest(address asset) internal {
        Market storage market = markets[asset];
        
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - market.lastUpdateTime;
        
        if (timeElapsed == 0) return;
        
        market.lastUpdateTime = currentTime;
        
        if (market.totalBorrows == 0) return;
        
        // Calculate interest
        uint256 borrowRate = interestRateModel.getBorrowRate(
            market.totalBorrows,
            market.totalSupply
        );
        
        uint256 interestAccumulated = (market.totalBorrows * borrowRate * timeElapsed) / PRECISION;
        
        // Update borrow index
        uint256 indexDelta = (interestAccumulated * PRECISION) / market.totalBorrows;
        market.borrowIndex += indexDelta;
        
        // Add interest to total borrows
        market.totalBorrows += interestAccumulated;
        
        // Add reserves
        uint256 reserveIncrease = (interestAccumulated * market.reserveFactor) / PRECISION;
        market.totalReserves += reserveIncrease;
        
        // Increase total supply by interest minus reserves
        market.totalSupply += interestAccumulated - reserveIncrease;
        
        emit InterestAccrued(asset, interestAccumulated, market.borrowIndex);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get user's borrow balance with interest
     */
    function borrowBalance(address user, address asset) external view returns (uint256) {
        return _borrowBalance(user, asset);
    }
    
    function _borrowBalance(address user, address asset) internal view returns (uint256) {
        BorrowSnapshot storage snapshot = borrowSnapshots[user][asset];
        if (snapshot.principal == 0) return 0;
        
        Market storage market = markets[asset];
        
        // Calculate current index with pending interest
        uint256 currentIndex = market.borrowIndex;
        uint256 timeElapsed = block.timestamp - market.lastUpdateTime;
        
        if (timeElapsed > 0 && market.totalBorrows > 0) {
            uint256 borrowRate = interestRateModel.getBorrowRate(
                market.totalBorrows,
                market.totalSupply
            );
            uint256 interestAccumulated = (market.totalBorrows * borrowRate * timeElapsed) / PRECISION;
            uint256 indexDelta = (interestAccumulated * PRECISION) / market.totalBorrows;
            currentIndex += indexDelta;
        }
        
        // principal * currentIndex / borrowIndex
        return (snapshot.principal * currentIndex) / snapshot.borrowIndex;
    }
    
    /**
     * @notice Get user's health factor
     */
    function healthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
    
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalCollateralValue, uint256 totalBorrowValue) = _getUserAccountData(user);
        
        if (totalBorrowValue == 0) return type(uint256).max;
        
        return (totalCollateralValue * PRECISION) / totalBorrowValue;
    }
    
    /**
     * @notice Get user's total collateral and borrow values
     */
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralValue,
        uint256 totalBorrowValue,
        uint256 availableBorrowValue,
        uint256 currentHealthFactor
    ) {
        (totalCollateralValue, totalBorrowValue) = _getUserAccountData(user);
        
        if (totalBorrowValue == 0) {
            currentHealthFactor = type(uint256).max;
            availableBorrowValue = totalCollateralValue;
        } else {
            currentHealthFactor = (totalCollateralValue * PRECISION) / totalBorrowValue;
            availableBorrowValue = totalCollateralValue > totalBorrowValue 
                ? totalCollateralValue - totalBorrowValue 
                : 0;
        }
    }
    
    function _getUserAccountData(address user) internal view returns (
        uint256 totalCollateralValue,
        uint256 totalBorrowValue
    ) {
        // Calculate collateral value
        address[] storage collaterals = userCollateralAssets[user];
        for (uint256 i = 0; i < collaterals.length; i++) {
            address asset = collaterals[i];
            if (userCollateral[user][asset]) {
                uint256 balance = _userAssetBalance(user, asset);
                uint256 value = _getAssetValue(asset, balance);
                uint256 adjustedValue = (value * markets[asset].liquidationThreshold) / PRECISION;
                totalCollateralValue += adjustedValue;
            }
        }
        
        // Calculate borrow value
        address[] storage borrows = userBorrowedAssets[user];
        for (uint256 i = 0; i < borrows.length; i++) {
            address asset = borrows[i];
            uint256 borrowBal = _borrowBalance(user, asset);
            if (borrowBal > 0) {
                totalBorrowValue += _getAssetValue(asset, borrowBal);
            }
        }
    }
    
    /**
     * @notice Get user's underlying balance for an asset
     */
    function userAssetBalance(address user, address asset) external view returns (uint256) {
        return _userAssetBalance(user, asset);
    }
    
    function _userAssetBalance(address user, address asset) internal view returns (uint256) {
        Market storage market = markets[asset];
        uint256 shares = market.aToken.balanceOf(user);
        return market.aToken.sharesToUnderlying(shares, market.totalSupply);
    }
    
    /**
     * @notice Get market rates
     */
    function getMarketRates(address asset) external view returns (
        uint256 supplyAPR,
        uint256 borrowAPR,
        uint256 utilization
    ) {
        Market storage market = markets[asset];
        
        utilization = interestRateModel.getUtilizationRate(
            market.totalBorrows,
            market.totalSupply
        );
        
        borrowAPR = interestRateModel.getBorrowAPR(
            market.totalBorrows,
            market.totalSupply
        );
        
        supplyAPR = interestRateModel.getSupplyAPR(
            market.totalBorrows,
            market.totalSupply,
            market.reserveFactor
        );
    }
    
    /**
     * @notice Get all markets
     */
    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }
    
    /**
     * @notice Get market info
     */
    function getMarketInfo(address asset) external view returns (
        address aToken,
        uint256 totalSupply,
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 reserveFactor,
        bool isListed,
        bool canBorrow,
        bool canCollateral
    ) {
        Market storage market = markets[asset];
        return (
            address(market.aToken),
            market.totalSupply,
            market.totalBorrows,
            market.totalReserves,
            market.collateralFactor,
            market.liquidationThreshold,
            market.reserveFactor,
            market.isListed,
            market.canBorrow,
            market.canCollateral
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════
    
    function _getAssetValue(address asset, uint256 amount) internal view returns (uint256) {
        // Get price from oracle (18 decimal precision)
        uint256 price = IPriceOracle(priceOracle).getPrice(asset);
        // Get token decimals
        uint8 decimals = IERC20Metadata(asset).decimals();
        // Normalize amount to 18 decimals, then apply price
        // value = (amount * 10^(18 - decimals)) * price / 1e18
        if (decimals < 18) {
            return (amount * (10 ** (18 - decimals)) * price) / PRECISION;
        } else {
            return (amount * price) / PRECISION;
        }
    }
    
    function _getAssetAmount(address asset, uint256 value) internal view returns (uint256) {
        uint256 price = IPriceOracle(priceOracle).getPrice(asset);
        uint8 decimals = IERC20Metadata(asset).decimals();
        // Convert value back to asset amount with proper decimals
        if (decimals < 18) {
            return (value * PRECISION) / (price * (10 ** (18 - decimals)));
        } else {
            return (value * PRECISION) / price;
        }
    }
    
    function _removeFromBorrowedAssets(address user, address asset) internal {
        address[] storage assets = userBorrowedAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == asset) {
                assets[i] = assets[assets.length - 1];
                assets.pop();
                break;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata data
    ) external;
}
