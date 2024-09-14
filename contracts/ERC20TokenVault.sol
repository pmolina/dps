// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing the ERC20 interface and utility contracts from OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Importing the Aave V3 Pool interface for interacting with the Aave lending protocol
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

/// @title ERC20 Token Vault
/// @notice A vault contract for depositing and managing ERC20 tokens with fallback and proof-of-life functionality.
contract ERC20TokenVault is ReentrancyGuard, Ownable, Pausable {
  // Immutable reference to the ERC20 token contract (e.g.: USDC)
  IERC20 public immutable token;

  // The aToken corresponding to our main token (e.g.: aUSDC from USDC)
  IERC20 public immutable aToken;

  // Immutable reference to the Aave lending pool contract
  IPool public immutable lendingPool;

  // Mapping to store user balances
  mapping(address => uint256) public balances;

  // Mapping to store the last proof-of-life timestamp for each user
  mapping(address => uint256) public lastProofOfLife;

  // Mapping to store fallback wallets for each user
  mapping(address => address) public fallbackWallets;

  // Minimum and maximum allowed fallback periods
  uint256 public constant MIN_FALLBACK_PERIOD = 90 days;
  uint256 public constant MAX_FALLBACK_PERIOD = 1095 days; // 3 years

  // Mapping to store individual fallback periods for each user
  mapping(address => uint256) public userFallbackPeriods;

  // Mapping to store user aToken balances
  mapping(address => uint256) public aBalances;

  // Event emitted when a user deposits tokens
  event Deposit(address indexed user, uint256 amount);

  // Event emitted when a user withdraws tokens
  event Withdrawal(address indexed user, uint256 amount);

  // Event emitted when a user's proof of life is updated
  event ProofOfLifeUpdated(address indexed user, uint256 timestamp);

  // Event emitted when a user sets a fallback wallet
  event FallbackWalletSet(address indexed user, address indexed fallbackWallet);

  // Event emitted when a fallback withdrawal is executed
  event FallbackWithdrawal(address indexed user, address indexed fallbackWallet, uint256 amount);

  // Event emitted when a user sets their fallback period
  event UserFallbackPeriodSet(address indexed user, uint256 period);

  // Event for investing
  event Invested(address indexed user, uint256 amount);

  // Event for deinvesting
  event Deinvested(address indexed user, uint256 amount);

  /// @notice Constructor to initialize the contract with token address and owner.
  /// @param _tokenAddress The address of the ERC20 token contract.
  /// @param _aTokenAddress The address of the aToken contract.
  /// @param _lendingPoolAddress The address of the Aave lending pool contract.
  /// @param initialOwner The address of the contract owner.
  constructor(
    address _tokenAddress,
    address _aTokenAddress,
    address _lendingPoolAddress,
    address initialOwner
  ) Ownable(initialOwner) {
    // Initialize the ERC20 token interface
    token = IERC20(_tokenAddress);
    aToken = IERC20(_aTokenAddress);
    lendingPool = IPool(_lendingPoolAddress);
  }

  /// @notice Function to deposit tokens into the vault.
  /// @param _amount The amount of tokens to deposit.
  function deposit(uint256 _amount) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");

    // Transfer tokens from the user to the contract
    token.transferFrom(msg.sender, address(this), _amount);

    // Update the user's balance
    balances[msg.sender] += _amount;

    // Update the user's proof-of-life timestamp
    _updateProofOfLife(msg.sender);

    // Emit the deposit event
    emit Deposit(msg.sender, _amount);
  }

  /// @notice Function to set a fallback wallet.
  /// @param _fallbackWallet The address of the fallback wallet.
  function setFallbackWallet(address _fallbackWallet) external {
    require(_fallbackWallet != address(0), "Invalid fallback wallet");

    // Set the fallback wallet for the sender
    fallbackWallets[msg.sender] = _fallbackWallet;

    // Emit the event for setting a fallback wallet
    emit FallbackWalletSet(msg.sender, _fallbackWallet);
  }

  /// @notice Function to set the user's fallback period.
  /// @param _period The fallback period in seconds.
  function setUserFallbackPeriod(uint256 _period) external {
    require(_period >= MIN_FALLBACK_PERIOD, "Period too short");
    require(_period <= MAX_FALLBACK_PERIOD, "Period too long");

    // Set the fallback period for the sender
    userFallbackPeriods[msg.sender] = _period;

    // Emit the event for setting a fallback period
    emit UserFallbackPeriodSet(msg.sender, _period);
  }

  /// @notice Function to withdraw tokens from the vault.
  /// @param _amount The amount of tokens to withdraw.
  function withdraw(uint256 _amount) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(balances[msg.sender] >= _amount, "Insufficient balance");

    // Decrease the user's balance
    balances[msg.sender] -= _amount;

    // Transfer tokens back to the user
    token.transfer(msg.sender, _amount);

    // Update the user's proof-of-life timestamp
    _updateProofOfLife(msg.sender);

    // Emit the withdrawal event
    emit Withdrawal(msg.sender, _amount);
  }

  /// @notice Function to perform a fallback withdrawal.
  /// @param _user The address of the user whose funds are to be withdrawn.
  /// @param _amount The amount of tokens to withdraw.
  function fallbackWithdraw(address _user, uint256 _amount) external nonReentrant whenNotPaused {
    // Ensure the fallback period has elapsed since the last proof-of-life
    require(block.timestamp > lastProofOfLife[_user] + userFallbackPeriods[_user], "Fallback period not elapsed");

    // Get the fallback wallet address; use the user's address if none is set
    address fallbackWallet = fallbackWallets[_user];
    if (fallbackWallet == address(0)) {
      fallbackWallet = _user;
    }

    require(_amount > 0, "Amount must be greater than 0");
    require(balances[_user] >= _amount, "Insufficient balance");

    // Decrease the user's balance
    balances[_user] -= _amount;

    // Transfer tokens to the fallback wallet
    token.transfer(fallbackWallet, _amount);

    // Emit the fallback withdrawal event
    emit FallbackWithdrawal(_user, fallbackWallet, _amount);
  }

  /// @notice Function to update the user's proof-of-life without making a deposit.
  function updateProofOfLife() external whenNotPaused {
    _updateProofOfLife(msg.sender);
  }

  /// @notice Internal function to update the proof-of-life timestamp for a user.
  /// @param user The address of the user.
  function _updateProofOfLife(address user) internal {
    // Update the last proof-of-life timestamp to the current block timestamp
    lastProofOfLife[user] = block.timestamp;

    // Emit the proof-of-life updated event
    emit ProofOfLifeUpdated(user, block.timestamp);
  }

  /// @notice Function to invest user's funds into the Aave lending protocol
  /// @param _amount The amount of tokens to invest
  function invest(uint256 _amount) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(balances[msg.sender] >= _amount, "Insufficient balance");

    // Decrease the user's balance in the vault
    balances[msg.sender] -= _amount;

    // Approve the lending pool to spend tokens
    token.approve(address(lendingPool), _amount);

    // Record the current aToken balance of this contract
    uint256 aTokenBalanceBefore = aToken.balanceOf(address(this));

    // Deposit tokens into Aave
    lendingPool.supply(address(token), _amount, address(this), 0);

    // Calculate the amount of aTokens received
    uint256 aTokensReceived = aToken.balanceOf(address(this)) - aTokenBalanceBefore;

    // Update the user's aToken balance
    aBalances[msg.sender] += aTokensReceived;

    // Update the user's proof-of-life timestamp
    _updateProofOfLife(msg.sender);

    emit Invested(msg.sender, _amount);
  }

  /// @notice Function to deinvest user's funds from the Aave lending protocol
  /// @param _amount The amount of aTokens to deinvest
  function deinvest(uint256 _amount) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(aBalances[msg.sender] >= _amount, "Insufficient aToken balance");

    // Decrease the user's aToken balance
    aBalances[msg.sender] -= _amount;

    // Record the current token balance of this contract
    uint256 tokenBalanceBefore = token.balanceOf(address(this));

    // Withdraw tokens from Aave
    lendingPool.withdraw(address(token), _amount, address(this));

    // Calculate the amount of tokens received
    uint256 tokensReceived = token.balanceOf(address(this)) - tokenBalanceBefore;

    // Increase the user's balance in the vault
    balances[msg.sender] += tokensReceived;

    // Update the user's proof-of-life timestamp
    _updateProofOfLife(msg.sender);

    emit Deinvested(msg.sender, tokensReceived);
  }

  /// @notice Function to pause the contract (only callable by the owner).
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Function to unpause the contract (only callable by the owner).
  function unpause() external onlyOwner {
    _unpause();
  }
}
