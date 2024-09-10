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

    function testFallbackWithdraw() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        vault.setFallbackWallet(fallbackWallet);
        vault.setUserFallbackPeriod(90 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 91 days);

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
}
