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

  // Mapping to store client balances: manager address => clientID => balance
  mapping(address => mapping(bytes32 => uint256)) public balances;

  // Mapping to store the last proof-of-life timestamp for each client
  mapping(address => mapping(bytes32 => uint256)) public lastProofOfLife;

  // Mapping to store fallback wallets for each client
  mapping(address => mapping(bytes32 => address)) public fallbackWallets;

  // Minimum and maximum allowed fallback periods
  uint256 public constant MIN_FALLBACK_PERIOD = 90 days;
  uint256 public constant MAX_FALLBACK_PERIOD = 1095 days; // 3 years

  // Mapping to store individual fallback periods for each client
  mapping(address => mapping(bytes32 => uint256)) public userFallbackPeriods;

  // Mapping to store client aToken balances
  mapping(address => mapping(bytes32 => uint256)) public aBalances;

  // Event emitted when a user deposits tokens
  event Deposit(address indexed manager, bytes32 indexed clientID, uint256 amount);

  // Event emitted when a user withdraws tokens
  event Withdrawal(address indexed manager, bytes32 indexed clientID, uint256 amount);

  // Event emitted when a client's proof of life is updated
  event ProofOfLifeUpdated(address indexed manager, bytes32 indexed clientID, uint256 timestamp);

  // Event emitted when a manager sets a fallback wallet for a client
  event FallbackWalletSet(address indexed manager, bytes32 indexed clientID, address indexed fallbackWallet);

  // Event emitted when a fallback withdrawal is executed
  event FallbackWithdrawal(
    address indexed manager,
    bytes32 indexed clientID,
    address indexed fallbackWallet,
    uint256 amount
  );

  // Event emitted when a manager sets the fallback period for a client
  event UserFallbackPeriodSet(address indexed manager, bytes32 indexed clientID, uint256 period);

  // Event for investing
  event Invested(address indexed manager, bytes32 indexed clientID, uint256 amount);

  // Event for deinvesting
  event Deinvested(address indexed manager, bytes32 indexed clientID, uint256 amount);

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

  /// @notice Function to deposit tokens into the vault for a specific client.
  /// @param _amount The amount of tokens to deposit.
  /// @param clientID The unique identifier of the client.
  function deposit(uint256 _amount, bytes32 clientID) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");

    // Transfer tokens from the manager to the contract
    token.transferFrom(msg.sender, address(this), _amount);

    // Update the client's balance
    balances[msg.sender][clientID] += _amount;

    // Update the client's proof-of-life timestamp
    _updateProofOfLife(msg.sender, clientID);

    // Emit the deposit event
    emit Deposit(msg.sender, clientID, _amount);
  }

  /// @notice Function to set a fallback wallet for a specific client.
  /// @param clientID The unique identifier of the client.
  /// @param _fallbackWallet The address of the fallback wallet.
  function setFallbackWallet(bytes32 clientID, address _fallbackWallet) external {
    require(_fallbackWallet != address(0), "Invalid fallback wallet");

    // Set the fallback wallet for the client
    fallbackWallets[msg.sender][clientID] = _fallbackWallet;

    // Emit the event for setting a fallback wallet
    emit FallbackWalletSet(msg.sender, clientID, _fallbackWallet);
  }

  /// @notice Function to set the fallback period for a specific client.
  /// @param clientID The unique identifier of the client.
  /// @param _period The fallback period in seconds.
  function setUserFallbackPeriod(bytes32 clientID, uint256 _period) external {
    require(_period >= MIN_FALLBACK_PERIOD, "Period too short");
    require(_period <= MAX_FALLBACK_PERIOD, "Period too long");

    // Set the fallback period for the client
    userFallbackPeriods[msg.sender][clientID] = _period;

    // Emit the event for setting a fallback period
    emit UserFallbackPeriodSet(msg.sender, clientID, _period);
  }

  /// @notice Function to withdraw tokens from the vault for a specific client.
  /// @param _amount The amount of tokens to withdraw.
  /// @param clientID The unique identifier of the client.
  function withdraw(uint256 _amount, bytes32 clientID) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(balances[msg.sender][clientID] >= _amount, "Insufficient balance");

    // Decrease the client's balance
    balances[msg.sender][clientID] -= _amount;

    // Transfer tokens back to the manager
    token.transfer(msg.sender, _amount);

    // Update the client's proof-of-life timestamp
    _updateProofOfLife(msg.sender, clientID);

    // Emit the withdrawal event
    emit Withdrawal(msg.sender, clientID, _amount);
  }

  /// @notice Function to perform a fallback withdrawal for a specific client.
  /// @param _manager The address of the manager.
  /// @param clientID The unique identifier of the client.
  /// @param _amount The amount of tokens to withdraw.
  function fallbackWithdraw(address _manager, bytes32 clientID, uint256 _amount) external nonReentrant whenNotPaused {
    // Ensure the fallback period has elapsed since the last proof-of-life
    require(
      block.timestamp > lastProofOfLife[_manager][clientID] + userFallbackPeriods[_manager][clientID],
      "Fallback period not elapsed"
    );

    // Get the fallback wallet address; use the manager's address if none is set
    address fallbackWallet = fallbackWallets[_manager][clientID];
    if (fallbackWallet == address(0)) {
      fallbackWallet = _manager;
    }

    require(_amount > 0, "Amount must be greater than 0");
    require(balances[_manager][clientID] >= _amount, "Insufficient balance");

    // Decrease the client's balance
    balances[_manager][clientID] -= _amount;

    // Transfer tokens to the fallback wallet
    token.transfer(fallbackWallet, _amount);

    // Emit the fallback withdrawal event
    emit FallbackWithdrawal(_manager, clientID, fallbackWallet, _amount);
  }

  /// @notice Function to update the proof-of-life for a specific client without making a deposit.
  /// @param clientID The unique identifier of the client.
  function updateProofOfLife(bytes32 clientID) external whenNotPaused {
    _updateProofOfLife(msg.sender, clientID);
  }

  /// @notice Internal function to update the proof-of-life timestamp for a client.
  /// @param manager The address of the manager.
  /// @param clientID The unique identifier of the client.
  function _updateProofOfLife(address manager, bytes32 clientID) internal {
    // Update the last proof-of-life timestamp to the current block timestamp
    lastProofOfLife[manager][clientID] = block.timestamp;

    // Emit the proof-of-life updated event
    emit ProofOfLifeUpdated(manager, clientID, block.timestamp);
  }

  /// @notice Function to invest a client's funds into the Aave lending protocol
  /// @param _amount The amount of tokens to invest
  /// @param clientID The unique identifier of the client.
  function invest(uint256 _amount, bytes32 clientID) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(balances[msg.sender][clientID] >= _amount, "Insufficient balance");

    // Decrease the client's balance in the vault
    balances[msg.sender][clientID] -= _amount;

    // Approve the lending pool to spend tokens
    token.approve(address(lendingPool), _amount);

    // Record the current aToken balance of this contract
    uint256 aTokenBalanceBefore = aToken.balanceOf(address(this));

    // Deposit tokens into Aave
    lendingPool.supply(address(token), _amount, address(this), 0);

    // Calculate the amount of aTokens received
    uint256 aTokensReceived = aToken.balanceOf(address(this)) - aTokenBalanceBefore;

    // Update the client's aToken balance
    aBalances[msg.sender][clientID] += aTokensReceived;

    // Update the client's proof-of-life timestamp
    _updateProofOfLife(msg.sender, clientID);

    emit Invested(msg.sender, clientID, _amount);
  }

  /// @notice Function to deinvest a client's funds from the Aave lending protocol
  /// @param _amount The amount of aTokens to deinvest
  /// @param clientID The unique identifier of the client.
  function deinvest(uint256 _amount, bytes32 clientID) external nonReentrant whenNotPaused {
    require(_amount > 0, "Amount must be greater than 0");
    require(aBalances[msg.sender][clientID] >= _amount, "Insufficient aToken balance");

    // Decrease the client's aToken balance
    aBalances[msg.sender][clientID] -= _amount;

    // Record the current token balance of this contract
    uint256 tokenBalanceBefore = token.balanceOf(address(this));

    // Withdraw tokens from Aave
    lendingPool.withdraw(address(token), _amount, address(this));

    // Calculate the amount of tokens received
    uint256 tokensReceived = token.balanceOf(address(this)) - tokenBalanceBefore;

    // Increase the client's balance in the vault
    balances[msg.sender][clientID] += tokensReceived;

    // Update the client's proof-of-life timestamp
    _updateProofOfLife(msg.sender, clientID);

    emit Deinvested(msg.sender, clientID, tokensReceived);
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
