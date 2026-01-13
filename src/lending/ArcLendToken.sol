// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ArcLendToken
 * @author ChordSwap
 * @notice Interest-bearing token representing supplied assets
 * @dev Similar to Aave's aTokens - balance automatically increases with accrued interest
 * 
 * Key Features:
 * - Rebasing token: balances grow automatically as interest accrues
 * - 1:1 exchange rate at protocol start, grows over time
 * - Can be transferred, used as collateral elsewhere
 */
contract ArcLendToken is ERC20, Ownable {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice The underlying asset this token represents
    IERC20 public immutable underlyingAsset;
    
    /// @notice The lending pool that controls minting/burning
    address public lendingPool;
    
    /// @notice Decimals matching underlying asset
    uint8 private immutable _decimals;
    
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════
    
    event Mint(address indexed user, uint256 amount, uint256 shares);
    event Burn(address indexed user, uint256 amount, uint256 shares);
    event LendingPoolUpdated(address indexed oldPool, address indexed newPool);
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    
    error OnlyLendingPool();
    error InvalidAddress();
    error InvalidAmount();
    
    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════
    
    modifier onlyLendingPool() {
        if (msg.sender != lendingPool) revert OnlyLendingPool();
        _;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Create a new ArcLendToken
     * @param _name Token name (e.g., "Arc Lending USDC")
     * @param _symbol Token symbol (e.g., "aUSDC")
     * @param _underlying The underlying ERC20 asset
     */
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        if (address(_underlying) == address(0)) revert InvalidAddress();
        underlyingAsset = _underlying;
        
        // Try to get decimals from underlying, default to 18
        try IERC20Metadata(address(_underlying)).decimals() returns (uint8 dec) {
            _decimals = dec;
        } catch {
            _decimals = 18;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Set the lending pool address
     * @param _lendingPool The lending pool contract
     */
    function setLendingPool(address _lendingPool) external onlyOwner {
        if (_lendingPool == address(0)) revert InvalidAddress();
        emit LendingPoolUpdated(lendingPool, _lendingPool);
        lendingPool = _lendingPool;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // LENDING POOL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Mint aTokens when user supplies assets
     * @param user The user receiving aTokens
     * @param amount The amount of underlying supplied
     * @param poolTotalUnderlying Total underlying in the pool
     * @return shares The number of shares minted
     */
    function mint(
        address user,
        uint256 amount,
        uint256 poolTotalUnderlying
    ) external onlyLendingPool returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();
        
        uint256 currentTotalShares = totalSupply();
        
        if (currentTotalShares == 0 || poolTotalUnderlying == 0) {
            // First deposit: 1:1 ratio
            shares = amount;
        } else {
            // shares = amount * totalShares / totalUnderlying
            shares = (amount * currentTotalShares) / poolTotalUnderlying;
        }
        
        _mint(user, shares);
        emit Mint(user, amount, shares);
    }
    
    /**
     * @notice Burn aTokens when user withdraws
     * @param user The user burning aTokens
     * @param shares The number of shares to burn
     * @param poolTotalUnderlying Total underlying in the pool
     * @return amount The amount of underlying to return
     */
    function burn(
        address user,
        uint256 shares,
        uint256 poolTotalUnderlying
    ) external onlyLendingPool returns (uint256 amount) {
        if (shares == 0) revert InvalidAmount();
        
        uint256 currentTotalShares = totalSupply();
        
        // amount = shares * totalUnderlying / totalShares
        amount = (shares * poolTotalUnderlying) / currentTotalShares;
        
        _burn(user, shares);
        emit Burn(user, amount, shares);
    }
    
    /**
     * @notice Burn exact amount of underlying worth of shares
     * @param user The user burning aTokens
     * @param amount The amount of underlying to withdraw
     * @param poolTotalUnderlying Total underlying in the pool
     * @return shares The number of shares burned
     */
    function burnAmount(
        address user,
        uint256 amount,
        uint256 poolTotalUnderlying
    ) external onlyLendingPool returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();
        
        uint256 currentTotalShares = totalSupply();
        
        // shares = amount * totalShares / totalUnderlying
        shares = (amount * currentTotalShares) / poolTotalUnderlying;
        
        _burn(user, shares);
        emit Burn(user, amount, shares);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get decimals (matches underlying)
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Calculate underlying value of shares
     * @param shares Number of aToken shares
     * @param totalUnderlying Total underlying in pool
     * @return The underlying value
     */
    function sharesToUnderlying(
        uint256 shares,
        uint256 totalUnderlying
    ) external view returns (uint256) {
        uint256 currentTotalShares = totalSupply();
        if (currentTotalShares == 0) return shares;
        return (shares * totalUnderlying) / currentTotalShares;
    }
    
    /**
     * @notice Calculate shares for underlying amount
     * @param amount Underlying amount
     * @param totalUnderlying Total underlying in pool
     * @return The number of shares
     */
    function underlyingToShares(
        uint256 amount,
        uint256 totalUnderlying
    ) external view returns (uint256) {
        uint256 currentTotalShares = totalSupply();
        if (currentTotalShares == 0 || totalUnderlying == 0) return amount;
        return (amount * currentTotalShares) / totalUnderlying;
    }
    
    /**
     * @notice Get the exchange rate (underlying per share)
     * @param totalUnderlying Total underlying in pool
     * @return Exchange rate in 1e18 precision
     */
    function exchangeRate(uint256 totalUnderlying) external view returns (uint256) {
        uint256 currentTotalShares = totalSupply();
        if (currentTotalShares == 0) return 1e18;
        return (totalUnderlying * 1e18) / currentTotalShares;
    }
}
