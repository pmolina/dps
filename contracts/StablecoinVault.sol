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

    // Mapping to store the last proof of life timestamp for each user
    mapping(address => uint256) private lastProofOfLife;

    // Event emitted when a user deposits tokens
    event Deposit(address indexed user, address indexed token, uint256 amount);
    // Event emitted when a user withdraws tokens
    event Withdrawal(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    // New event for proof of life updates
    event ProofOfLifeUpdated(address indexed user, uint256 timestamp);

    // Constructor to initialize the contract with token addresses and set the owner
    constructor(
        address _usdcAddress,
        address _usdtAddress,
        address initialOwner
    ) {
        // Initialize USDC and USDT token interfaces
        USDC = IERC20(_usdcAddress);
        USDT = IERC20(_usdtAddress);

        // Set the contract owner
        // If initialOwner is the zero address, set msg.sender as the owner
        // Otherwise, set the provided initialOwner as the owner
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

        // Update proof of life
        _updateProofOfLife(msg.sender);

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

    // Function to update proof of life without making a deposit
    function updateProofOfLife() external whenNotPaused {
        _updateProofOfLife(msg.sender);
    }

    // Internal function to update proof of life
    function _updateProofOfLife(address user) internal {
        lastProofOfLife[user] = block.timestamp;
        emit ProofOfLifeUpdated(user, block.timestamp);
    }

    // Function to get the last proof of life timestamp for a user
    function getLastProofOfLife(address user) external view returns (uint256) {
        return lastProofOfLife[user];
    }

    // New functions for pausing and unpausing
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
