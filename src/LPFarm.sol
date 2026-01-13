// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChordToken
 * @notice Reward token for ChordSwap farming
 */
contract ChordToken is IERC20, Ownable {
    string public constant name = "ChordSwap Token";
    string public constant symbol = "CHORD";
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Minters (farming contracts)
    mapping(address => bool) public minters;
    
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18; // 100M max

    constructor() Ownable(msg.sender) {
        // Mint initial supply to deployer for liquidity
        _mint(msg.sender, 10_000_000 * 1e18); // 10M initial
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            _approve(from, msg.sender, currentAllowance - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "Not a minter");
        require(_totalSupply + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }

    function setMinter(address minter, bool allowed) external onlyOwner {
        minters[minter] = allowed;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        require(_balances[from] >= amount, "Insufficient balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title LPFarm
 * @notice Stake LP tokens to earn CHORD rewards
 * @dev MasterChef-style farming with multiple pools
 */
contract LPFarm is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user
    struct UserInfo {
        uint256 amount;           // LP tokens staked
        uint256 rewardDebt;       // Reward debt
        uint256 pendingRewards;   // Pending rewards to claim
        uint256 lastStakeTime;    // Last stake timestamp
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 lpToken;           // LP token contract
        uint256 allocPoint;       // Allocation points
        uint256 lastRewardTime;   // Last reward distribution
        uint256 accRewardPerShare; // Accumulated rewards per share
        uint256 totalStaked;      // Total LP staked
        uint256 depositFee;       // Deposit fee (basis points, max 400 = 4%)
    }

    // Reward token
    ChordToken public rewardToken;
    
    // Rewards per second
    uint256 public rewardPerSecond;
    
    // Total allocation points
    uint256 public totalAllocPoint;
    
    // Start time
    uint256 public startTime;
    
    // Pool info
    PoolInfo[] public poolInfo;
    
    // User info: poolId => user => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    // Fee collector
    address public feeCollector;
    
    // Events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address lpToken, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    constructor(
        address _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _startTime
    ) Ownable(msg.sender) {
        rewardToken = ChordToken(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
        startTime = _startTime;
        feeCollector = msg.sender;
    }

    // ============ View Functions ============

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        
        uint256 accRewardPerShare = pool.accRewardPerShare;
        
        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 reward = (timeElapsed * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare += (reward * 1e12) / pool.totalStaked;
        }
        
        return user.pendingRewards + ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    function getPoolInfo(uint256 _pid) external view returns (
        address lpToken,
        uint256 allocPoint,
        uint256 totalStaked,
        uint256 depositFee,
        uint256 accRewardPerShare
    ) {
        PoolInfo memory pool = poolInfo[_pid];
        return (
            address(pool.lpToken),
            pool.allocPoint,
            pool.totalStaked,
            pool.depositFee,
            pool.accRewardPerShare
        );
    }

    function getUserInfo(uint256 _pid, address _user) external view returns (
        uint256 amount,
        uint256 pending,
        uint256 lastStakeTime
    ) {
        UserInfo memory user = userInfo[_pid][_user];
        return (
            user.amount,
            this.pendingReward(_pid, _user),
            user.lastStakeTime
        );
    }

    // ============ User Functions ============

    /**
     * @notice Deposit LP tokens to farm
     */
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "Invalid pool");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        updatePool(_pid);
        
        // Calculate pending rewards
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
            user.pendingRewards += pending;
        }
        
        if (_amount > 0) {
            // Transfer LP tokens
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 received = pool.lpToken.balanceOf(address(this)) - balanceBefore;
            
            // Deduct deposit fee
            if (pool.depositFee > 0) {
                uint256 fee = (received * pool.depositFee) / 10000;
                pool.lpToken.safeTransfer(feeCollector, fee);
                received -= fee;
            }
            
            user.amount += received;
            pool.totalStaked += received;
            user.lastStakeTime = block.timestamp;
        }
        
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        
        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice Withdraw LP tokens from farm
     */
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "Invalid pool");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        require(user.amount >= _amount, "Insufficient balance");
        
        updatePool(_pid);
        
        // Calculate pending rewards
        uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        user.pendingRewards += pending;
        
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * @notice Claim pending rewards
     */
    function claim(uint256 _pid) external nonReentrant {
        require(_pid < poolInfo.length, "Invalid pool");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        updatePool(_pid);
        
        uint256 pending = user.pendingRewards + 
            ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        
        require(pending > 0, "Nothing to claim");
        
        user.pendingRewards = 0;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        
        // Mint rewards
        rewardToken.mint(msg.sender, pending);
        
        emit Claim(msg.sender, _pid, pending);
    }

    /**
     * @notice Emergency withdraw without rewards
     */
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        require(_pid < poolInfo.length, "Invalid pool");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
        pool.totalStaked -= amount;
        
        pool.lpToken.safeTransfer(msg.sender, amount);
        
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // ============ Internal Functions ============

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        
        if (pool.totalStaked == 0 || totalAllocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 reward = (timeElapsed * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
        
        pool.accRewardPerShare += (reward * 1e12) / pool.totalStaked;
        pool.lastRewardTime = block.timestamp;
    }

    // ============ Admin Functions ============

    function addPool(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint256 _depositFee,
        bool _withUpdate
    ) external onlyOwner {
        require(_depositFee <= 400, "Fee too high"); // Max 4%
        
        if (_withUpdate) {
            massUpdatePools();
        }
        
        totalAllocPoint += _allocPoint;
        
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
            accRewardPerShare: 0,
            totalStaked: 0,
            depositFee: _depositFee
        }));
        
        emit PoolAdded(poolInfo.length - 1, address(_lpToken), _allocPoint);
    }

    function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        
        emit PoolUpdated(_pid, _allocPoint);
    }

    function massUpdatePools() public {
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            updatePool(pid);
        }
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        massUpdatePools();
        rewardPerSecond = _rewardPerSecond;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }
}
