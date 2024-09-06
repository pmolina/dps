// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract StablecoinVault is ReentrancyGuard, Ownable, Pausable {
    // Immutable references to the USDC and USDT token contracts
    IERC20 public immutable USDC;
    IERC20 public immutable USDT;

    // Nested mapping to store user balances for each token
    // user address => token address => balance
    mapping(address => mapping(address => uint256)) private balances;

    // Event emitted when a user deposits tokens
    event Deposit(address indexed user, address indexed token, uint256 amount);
    // Event emitted when a user withdraws tokens
    event Withdrawal(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    // Constructor to set the addresses of USDC and USDT tokens
    constructor(
        address _usdcAddress,
        address _usdtAddress,
        address initialOwner
    ) {
        USDC = IERC20(_usdcAddress);
        USDT = IERC20(_usdtAddress);
        _transferOwnership(
            initialOwner == address(0) ? msg.sender : initialOwner
        );
    }

    // Function to deposit tokens into the vault
    function deposit(
        address _token,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        require(
            _token == address(USDC) || _token == address(USDT),
            "Invalid token"
        );
        require(_amount > 0, "Amount must be greater than 0");

        // Transfer tokens from user to the contract
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // Update user's balance
        balances[msg.sender][_token] += _amount;

        emit Deposit(msg.sender, _token, _amount);
    }

    // Function to withdraw tokens from the vault
    function withdraw(
        address _token,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        require(
            _token == address(USDC) || _token == address(USDT),
            "Invalid token"
        );
        require(_amount > 0, "Amount must be greater than 0");
        require(
            balances[msg.sender][_token] >= _amount,
            "Insufficient balance"
        );

        // Update user's balance
        balances[msg.sender][_token] -= _amount;
        // Transfer tokens from the contract to the user
        IERC20(_token).transfer(msg.sender, _amount);

        emit Withdrawal(msg.sender, _token, _amount);
    }

    // Function to get the balance of a user for a specific token
    function getBalance(
        address _user,
        address _token
    ) external view returns (uint256) {
        return balances[_user][_token];
    }

    // New functions for pausing and unpausing
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
