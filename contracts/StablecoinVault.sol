// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract StablecoinVault is ReentrancyGuard, Ownable, Pausable {
    // Immutable references to the USDC, USDT, and DAI token contracts
    IERC20 public immutable USDC;
    IERC20 public immutable USDT;
    IERC20 public immutable DAI;

    // Nested mapping to store user balances for each token
    // user address => token address => balance
    mapping(address => mapping(address => uint256)) private balances;

    // Mapping to store the last proof of life timestamp for each user
    mapping(address => uint256) private lastProofOfLife;

    // Mapping to store fallback wallets for each user
    mapping(address => address) public fallbackWallets;

    // Minimum and maximum fallback periods
    uint256 public constant MIN_FALLBACK_PERIOD = 90 days;
    uint256 public constant MAX_FALLBACK_PERIOD = 1095 days; // 3 years

    // Mapping to store individual fallback periods for each user
    mapping(address => uint256) public userFallbackPeriods;

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
    // New events for fallback wallet functionality
    event FallbackWalletSet(
        address indexed user,
        address indexed fallbackWallet
    );
    event FallbackWithdrawal(
        address indexed user,
        address indexed fallbackWallet,
        address indexed token,
        uint256 amount
    );
    // New event for setting individual fallback period
    event UserFallbackPeriodSet(address indexed user, uint256 period);

    // Constructor to initialize the contract with token addresses and set the owner
    constructor(
        address _usdcAddress,
        address _usdtAddress,
        address _daiAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        // Initialize USDC and USDT token interfaces
        USDC = IERC20(_usdcAddress);
        USDT = IERC20(_usdtAddress);
        DAI = IERC20(_daiAddress);
    }

    // Function to deposit tokens into the vault
    function deposit(
        address _token,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        require(
            _token == address(USDC) ||
                _token == address(USDT) ||
                _token == address(DAI),
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

    // Sets fallback wallet
    function setFallbackWallet(address _fallbackWallet) external {
        require(_fallbackWallet != address(0), "Invalid fallback wallet");
        fallbackWallets[msg.sender] = _fallbackWallet;
        emit FallbackWalletSet(msg.sender, _fallbackWallet);
    }

    // Sets user's fallback period
    function setUserFallbackPeriod(uint256 _period) external {
        require(_period >= MIN_FALLBACK_PERIOD, "Period too short");
        require(_period <= MAX_FALLBACK_PERIOD, "Period too long");
        userFallbackPeriods[msg.sender] = _period;
        emit UserFallbackPeriodSet(msg.sender, _period);
    }

    // Function to withdraw tokens from the vault
    function withdraw(
        address _token,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        require(
            _token == address(USDC) ||
                _token == address(USDT) ||
                _token == address(DAI),
            "Invalid token"
        );
        require(_amount > 0, "Amount must be greater than 0");
        require(
            balances[msg.sender][_token] >= _amount,
            "Insufficient balance"
        );

        balances[msg.sender][_token] -= _amount;
        IERC20(_token).transfer(msg.sender, _amount);

        _updateProofOfLife(msg.sender);

        emit Withdrawal(msg.sender, _token, _amount);
    }

    // Function for fallback withdrawal
    function fallbackWithdraw(
        address _user,
        address _token,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        require(
            block.timestamp >
                lastProofOfLife[_user] + userFallbackPeriods[_user],
            "Fallback period not elapsed"
        );

        address fallbackWallet = fallbackWallets[_user];
        if (fallbackWallet == address(0)) {
            fallbackWallet = _user; // Use the user's address if no fallback wallet is set
        }

        require(
            _token == address(USDC) ||
                _token == address(USDT) ||
                _token == address(DAI),
            "Invalid token"
        );
        require(_amount > 0, "Amount must be greater than 0");
        require(balances[_user][_token] >= _amount, "Insufficient balance");

        balances[_user][_token] -= _amount;
        IERC20(_token).transfer(fallbackWallet, _amount);

        emit FallbackWithdrawal(_user, fallbackWallet, _token, _amount);
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
