// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/ERC20TokenVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ERC20TokenVaultTest is Test {
    ERC20TokenVault public vault;
    MockERC20 public token;
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
        vault = new ERC20TokenVault(address(token), owner);

        token.mint(user1, INITIAL_SUPPLY);
        vm.prank(user1);
        token.approve(address(vault), INITIAL_SUPPLY);
    }

    function testDeposit() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.getBalance(user1), DEPOSIT_AMOUNT);
    }

    function testWithdraw() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        vault.withdraw(DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(vault.getBalance(user1), 0);
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

        assertEq(vault.getBalance(user1), 0);
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
        assertEq(vault.getBalance(user1), DEPOSIT_AMOUNT);
    }

    function testUpdateProofOfLife() public {
        vm.prank(user1);
        vault.updateProofOfLife();
        assertEq(vault.getLastProofOfLife(user1), block.timestamp);
    }

    function testDepositUpdatesProofOfLife() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.getLastProofOfLife(user1), block.timestamp);
    }

    function testWithdrawUpdatesProofOfLife() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.warp(block.timestamp + 1 days);
        vault.withdraw(DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertEq(vault.getLastProofOfLife(user1), block.timestamp);
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

        assertEq(vault.getBalance(user1), 0);
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
