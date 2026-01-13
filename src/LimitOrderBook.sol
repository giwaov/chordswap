// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IArcRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) 
        external view returns (uint256 amountOut);
}

/**
 * @title LimitOrderBook
 * @notice Limit order system for ChordSwap DEX
 * @dev Allows users to place orders that execute when price conditions are met
 */
contract LimitOrderBook is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Order structure
    struct Order {
        address owner;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;     // Minimum output (acts as limit price)
        uint256 createdAt;
        uint256 expiresAt;
        bool isActive;
    }

    // State
    IArcRouter public router;
    uint256 public nextOrderId;
    uint256 public executorFee = 50; // 0.5% fee for executors (basis points)
    uint256 public constant MAX_FEE = 100; // 1% max fee
    
    // Order storage
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;
    
    // Events
    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 expiresAt
    );
    
    event OrderExecuted(
        uint256 indexed orderId,
        address indexed executor,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executorReward
    );
    
    event OrderCancelled(uint256 indexed orderId, address indexed owner);
    event ExecutorFeeUpdated(uint256 newFee);

    constructor(address _router) Ownable(msg.sender) {
        router = IArcRouter(_router);
    }

    // ============ User Functions ============

    /**
     * @notice Create a new limit order
     * @param tokenIn Token to sell
     * @param tokenOut Token to buy
     * @param amountIn Amount to sell
     * @param minAmountOut Minimum amount to receive (limit price)
     * @param duration How long the order is valid (seconds)
     */
    function createOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 duration
    ) external nonReentrant returns (uint256 orderId) {
        require(amountIn > 0, "Invalid amount");
        require(minAmountOut > 0, "Invalid min output");
        require(duration > 0 && duration <= 30 days, "Invalid duration");
        require(tokenIn != tokenOut, "Same token");
        
        // Transfer tokens to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        orderId = nextOrderId++;
        
        orders[orderId] = Order({
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            isActive: true
        });
        
        userOrders[msg.sender].push(orderId);
        
        emit OrderCreated(
            orderId,
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            block.timestamp + duration
        );
    }

    /**
     * @notice Cancel an active order
     * @param orderId The order to cancel
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Not owner");
        require(order.isActive, "Order not active");
        
        order.isActive = false;
        
        // Refund tokens
        IERC20(order.tokenIn).safeTransfer(msg.sender, order.amountIn);
        
        emit OrderCancelled(orderId, msg.sender);
    }

    /**
     * @notice Execute a limit order (anyone can call when conditions are met)
     * @param orderId The order to execute
     */
    function executeOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.isActive, "Order not active");
        require(block.timestamp <= order.expiresAt, "Order expired");
        
        // Check if current price meets the limit
        uint256 currentAmountOut = router.getAmountOut(
            order.amountIn,
            order.tokenIn,
            order.tokenOut
        );
        require(currentAmountOut >= order.minAmountOut, "Price not met");
        
        order.isActive = false;
        
        // Calculate executor reward
        uint256 executorReward = (order.amountIn * executorFee) / 10000;
        uint256 swapAmount = order.amountIn - executorReward;
        
        // Approve router
        IERC20(order.tokenIn).approve(address(router), swapAmount);
        
        // Execute swap
        address[] memory path = new address[](2);
        path[0] = order.tokenIn;
        path[1] = order.tokenOut;
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            (order.minAmountOut * (10000 - executorFee)) / 10000, // Adjust for fee
            path,
            order.owner,
            block.timestamp
        );
        
        // Pay executor
        if (executorReward > 0) {
            IERC20(order.tokenIn).safeTransfer(msg.sender, executorReward);
        }
        
        emit OrderExecuted(
            orderId,
            msg.sender,
            order.amountIn,
            amounts[1],
            executorReward
        );
    }

    /**
     * @notice Claim expired order tokens
     * @param orderId The expired order
     */
    function claimExpired(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Not owner");
        require(order.isActive, "Order not active");
        require(block.timestamp > order.expiresAt, "Not expired");
        
        order.isActive = false;
        
        IERC20(order.tokenIn).safeTransfer(msg.sender, order.amountIn);
        
        emit OrderCancelled(orderId, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Get all orders for a user
     */
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    /**
     * @notice Get active orders for a user
     */
    function getActiveOrders(address user) external view returns (Order[] memory) {
        uint256[] memory orderIds = userOrders[user];
        uint256 activeCount = 0;
        
        // Count active orders
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (orders[orderIds[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build array
        Order[] memory activeOrders = new Order[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (orders[orderIds[i]].isActive) {
                activeOrders[index] = orders[orderIds[i]];
                index++;
            }
        }
        
        return activeOrders;
    }

    /**
     * @notice Check if an order can be executed
     */
    function canExecute(uint256 orderId) external view returns (bool) {
        Order memory order = orders[orderId];
        if (!order.isActive || block.timestamp > order.expiresAt) {
            return false;
        }
        
        try router.getAmountOut(order.amountIn, order.tokenIn, order.tokenOut) returns (uint256 amountOut) {
            return amountOut >= order.minAmountOut;
        } catch {
            return false;
        }
    }

    /**
     * @notice Get the limit price of an order (output per input)
     */
    function getOrderLimitPrice(uint256 orderId) external view returns (uint256) {
        Order memory order = orders[orderId];
        if (order.amountIn == 0) return 0;
        return (order.minAmountOut * 1e18) / order.amountIn;
    }

    // ============ Admin Functions ============

    function setExecutorFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "Fee too high");
        executorFee = _fee;
        emit ExecutorFeeUpdated(_fee);
    }

    function setRouter(address _router) external onlyOwner {
        router = IArcRouter(_router);
    }
}
