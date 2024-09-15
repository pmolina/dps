// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/ERC20TokenVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pool } from "@aave/core-v3/contracts/protocol/pool/Pool.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

contract MockERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

contract MockPool is Pool {
  mapping(address => uint256) public supplies;
  mapping(address => uint256) public borrows;

  constructor(IPoolAddressesProvider provider) Pool(provider) {}

  function supply(address asset, uint256 amount, address onBehalfOf, uint16) public override {
    supplies[onBehalfOf] += amount;
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(address asset, uint256 amount, address to) public override returns (uint256) {
    require(supplies[msg.sender] >= amount, "Insufficient balance");
    supplies[msg.sender] -= amount;
    IERC20(asset).transfer(to, amount);
    return amount;
  }

  function borrow(address asset, uint256 amount, address onBehalfOf) public {
    borrows[onBehalfOf] += amount;
    IERC20(asset).transfer(msg.sender, amount);
  }

  function repay(address asset, uint256 amount, address onBehalfOf) public returns (uint256) {
    uint256 repayAmount = amount > borrows[onBehalfOf] ? borrows[onBehalfOf] : amount;
    borrows[onBehalfOf] -= repayAmount;
    IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
    return repayAmount;
  }
}

contract ERC20TokenVaultTest is Test {
  ERC20TokenVault public vault;
  MockERC20 public token;
  MockERC20 public aToken;
  MockPool public lendingPool;
  address public owner;
  address public user1;
  address public user2;
  address public fallbackWallet;

  uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;
  uint256 constant DEPOSIT_AMOUNT = 1_000 * 1e18;
  uint256 constant MIN_FALLBACK_PERIOD = 90 days;
  uint256 constant MAX_FALLBACK_PERIOD = 1095 days;

  function setUp() public {
    owner = address(this);
    user1 = address(0x1);
    user2 = address(0x2);
    fallbackWallet = address(0x3);

    token = new MockERC20("Test Token", "TEST");
    aToken = new MockERC20("Aave Test Token", "aTEST");

    // Create a mock IPoolAddressesProvider
    MockPoolAddressesProvider mockProvider = new MockPoolAddressesProvider();
    lendingPool = new MockPool(mockProvider);

    vault = new ERC20TokenVault(address(token), address(aToken), address(lendingPool), owner);

    token.mint(user1, INITIAL_SUPPLY);
    vm.prank(user1);
    token.approve(address(vault), INITIAL_SUPPLY);
  }

  function testDeposit() public {
    vm.prank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    assertEq(vault.balances(user1), DEPOSIT_AMOUNT);
  }

  function testWithdraw() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.withdraw(DEPOSIT_AMOUNT);
    vm.stopPrank();
    assertEq(vault.balances(user1), 0);
  }

  function testSetFallbackWallet() public {
    vm.prank(user1);
    vault.setFallbackWallet(fallbackWallet);
    assertEq(vault.fallbackWallets(user1), fallbackWallet);
  }

  function testSetUserFallbackPeriod() public {
    vm.prank(user1);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    assertEq(vault.userFallbackPeriods(user1), MIN_FALLBACK_PERIOD);
  }

  function testFallbackWithdraw() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.setFallbackWallet(fallbackWallet);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    vm.stopPrank();

    vm.warp(block.timestamp + MIN_FALLBACK_PERIOD + 1 days);

    vm.prank(user2);
    vault.fallbackWithdraw(user1, DEPOSIT_AMOUNT);

    assertEq(vault.balances(user1), 0);
    assertEq(token.balanceOf(fallbackWallet), DEPOSIT_AMOUNT);
  }

  function testPause() public {
    vault.pause();
    assertTrue(vault.paused());

    vm.expectRevert();
    vm.prank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
  }

  function testUnpause() public {
    vault.pause();
    vault.unpause();
    assertFalse(vault.paused());

    vm.prank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    assertEq(vault.balances(user1), DEPOSIT_AMOUNT);
  }

  function testUpdateProofOfLife() public {
    vm.prank(user1);
    vault.updateProofOfLife();
    assertEq(vault.lastProofOfLife(user1), block.timestamp);
  }

  function testDepositUpdatesProofOfLife() public {
    vm.prank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    assertEq(vault.lastProofOfLife(user1), block.timestamp);
  }

  function testWithdrawUpdatesProofOfLife() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + 1 days);
    vault.withdraw(DEPOSIT_AMOUNT);
    vm.stopPrank();
    assertEq(vault.lastProofOfLife(user1), block.timestamp);
  }

  function testFallbackWithdrawBeforePeriod() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.setFallbackWallet(fallbackWallet);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    vm.stopPrank();

    vm.warp(block.timestamp + MIN_FALLBACK_PERIOD - 1 days);

    vm.expectRevert("Fallback period not elapsed");
    vm.prank(user2);
    vault.fallbackWithdraw(user1, DEPOSIT_AMOUNT);
  }

  function testFallbackWithdrawWithoutSettingWallet() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    vm.stopPrank();

    vm.warp(block.timestamp + MIN_FALLBACK_PERIOD + 1 days);

    vm.prank(user2);
    vault.fallbackWithdraw(user1, DEPOSIT_AMOUNT);

    assertEq(vault.balances(user1), 0);
    assertEq(token.balanceOf(user1), INITIAL_SUPPLY);
  }

  function testSetFallbackPeriodTooShort() public {
    vm.prank(user1);
    vm.expectRevert("Period too short");
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD - 1 days);
  }

  function testSetFallbackPeriodTooLong() public {
    vm.prank(user1);
    vm.expectRevert("Period too long");
    vault.setUserFallbackPeriod(MAX_FALLBACK_PERIOD + 1 days);
  }

  function testDepositZeroAmount() public {
    vm.prank(user1);
    vm.expectRevert("Amount must be greater than 0");
    vault.deposit(0);
  }

  function testWithdrawZeroAmount() public {
    vm.prank(user1);
    vm.expectRevert("Amount must be greater than 0");
    vault.withdraw(0);
  }

  function testWithdrawInsufficientBalance() public {
    vm.prank(user1);
    vault.deposit(DEPOSIT_AMOUNT);

    vm.prank(user1);
    vm.expectRevert("Insufficient balance");
    vault.withdraw(DEPOSIT_AMOUNT + 1);
  }

  function testFallbackWithdrawZeroAmount() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.setFallbackWallet(fallbackWallet);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    vm.stopPrank();

    vm.warp(block.timestamp + MIN_FALLBACK_PERIOD + 1 days);

    vm.prank(user2);
    vm.expectRevert("Amount must be greater than 0");
    vault.fallbackWithdraw(user1, 0);
  }

  function testFallbackWithdrawInsufficientBalance() public {
    vm.startPrank(user1);
    vault.deposit(DEPOSIT_AMOUNT);
    vault.setFallbackWallet(fallbackWallet);
    vault.setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
    vm.stopPrank();

    vm.warp(block.timestamp + MIN_FALLBACK_PERIOD + 1 days);

    vm.prank(user2);
    vm.expectRevert("Insufficient balance");
    vault.fallbackWithdraw(user1, DEPOSIT_AMOUNT + 1);
  }

  /* TODO: fix tests
    function testNonOwnerCannotPause() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.pause();
    }

    function testNonOwnerCannotUnpause() public {
        vault.pause();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.unpause();
    }
    */
}

// Simple mock for IPoolAddressesProvider
contract MockPoolAddressesProvider is IPoolAddressesProvider {
  string private marketId;
  address private pool;
  address private poolConfigurator;
  address private priceOracle;
  address private aclManager;
  address private aclAdmin;
  address private priceOracleSentinel;
  address private poolDataProvider;
  address private lendingRateOracle;

  mapping(bytes32 => address) private addresses;

  function getMarketId() external view override returns (string memory) {
    return marketId;
  }

  function setMarketId(string calldata newMarketId) external override {
    marketId = newMarketId;
  }

  function getAddress(bytes32 id) external view override returns (address) {
    return addresses[id];
  }

  function setAddressAsProxy(bytes32 id, address impl) external override {
    addresses[id] = impl;
  }

  function setAddress(bytes32 id, address newAddress) external override {
    addresses[id] = newAddress;
  }

  function getPool() external view override returns (address) {
    return pool;
  }

  function setPoolImpl(address newPoolImpl) external override {
    pool = newPoolImpl;
  }

  function getPoolConfigurator() external view override returns (address) {
    return poolConfigurator;
  }

  function setPoolConfiguratorImpl(address newPoolConfiguratorImpl) external override {
    poolConfigurator = newPoolConfiguratorImpl;
  }

  function getPriceOracle() external view override returns (address) {
    return priceOracle;
  }

  function setPriceOracle(address newPriceOracle) external override {
    priceOracle = newPriceOracle;
  }

  function getACLManager() external view override returns (address) {
    return aclManager;
  }

  function setACLManager(address newAclManager) external override {
    aclManager = newAclManager;
  }

  function getACLAdmin() external view override returns (address) {
    return aclAdmin;
  }

  function setACLAdmin(address newAclAdmin) external override {
    aclAdmin = newAclAdmin;
  }

  function getPriceOracleSentinel() external view override returns (address) {
    return priceOracleSentinel;
  }

  function setPriceOracleSentinel(address newPriceOracleSentinel) external override {
    priceOracleSentinel = newPriceOracleSentinel;
  }

  function getPoolDataProvider() external view override returns (address) {
    return poolDataProvider;
  }

  function setPoolDataProvider(address newDataProvider) external override {
    poolDataProvider = newDataProvider;
  }

  function getLendingRateOracle() external view returns (address) {
    return lendingRateOracle;
  }

  function setLendingRateOracle(address newLendingRateOracle) external {
    lendingRateOracle = newLendingRateOracle;
  }
}
