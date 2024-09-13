const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC20TokenVault", function () {
  let ERC20TokenVault, tokenVault, owner, user1, user2, fallbackWallet;
  let ERC20Token;

  const INITIAL_SUPPLY = ethers.parseUnits("1000000", 18); // 1 million tokens
  const DEPOSIT_AMOUNT = ethers.parseUnits("1000", 18); // 1000 tokens
  const MIN_FALLBACK_PERIOD = 90 * 24 * 60 * 60; // 90 days in seconds
  const MAX_FALLBACK_PERIOD = 1095 * 24 * 60 * 60; // 3 years in seconds

  beforeEach(async function () {
    [owner, user1, user2, fallbackWallet] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockToken = await ethers.getContractFactory("MockERC20");
    ERC20Token = await MockToken.deploy("Test Token", "TEST", 18);

    await ERC20Token.mint(user1.address, INITIAL_SUPPLY);

    // Deploy ERC20TokenVault
    ERC20TokenVault = await ethers.getContractFactory("ERC20TokenVault");
    tokenVault = await ERC20TokenVault.deploy(
      await ERC20Token.getAddress(),
      owner.address
    );

    // Approve ERC20TokenVault to spend tokens
    await ERC20Token.connect(user1).approve(await tokenVault.getAddress(), INITIAL_SUPPLY);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await tokenVault.owner()).to.equal(owner.address);
    });

    it("Should set the correct token address", async function () {
      expect(await tokenVault.token()).to.equal(await ERC20Token.getAddress());
    });

    it("Should initialize with correct fallback period constants", async function () {
      const minFallbackPeriod = await tokenVault.MIN_FALLBACK_PERIOD();
      const maxFallbackPeriod = await tokenVault.MAX_FALLBACK_PERIOD();
      
      expect(minFallbackPeriod).to.equal(90 * 24 * 60 * 60); // 90 days in seconds
      expect(maxFallbackPeriod).to.equal(1095 * 24 * 60 * 60); // 3 years in seconds
    });

    it("Should not be paused initially", async function () {
      expect(await tokenVault.paused()).to.be.false;
    });

    it("Should have zero balance for ERC20 tokens initially", async function () {
      const balance = await tokenVault.balances(user1.address);
      expect(balance).to.equal(0);
    });

    it("Should not have any fallback wallets set initially", async function () {
      const fallbackWallet = await tokenVault.fallbackWallets(user1.address);
      expect(fallbackWallet).to.equal(ethers.ZeroAddress);
    });

    it("Should not have any user fallback periods set initially", async function () {
      const userFallbackPeriod = await tokenVault.userFallbackPeriods(user1.address);
      expect(userFallbackPeriod).to.equal(0);
    });
  });

  describe("Deposits", function () {
    it("Should allow deposits of ERC20 tokens", async function () {
      await expect(tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT))
        .to.emit(tokenVault, "Deposit")
        .withArgs(user1.address, DEPOSIT_AMOUNT);

      expect(await tokenVault.balances(user1.address)).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should reject deposits of zero amount", async function () {
      await expect(tokenVault.connect(user1).deposit(0))
        .to.be.revertedWith("Amount must be greater than 0");
    });

    it("Should update proof of life on deposit", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      const lastProofOfLife = await tokenVault.lastProofOfLife(user1.address);
      expect(lastProofOfLife).to.be.closeTo(
        (await ethers.provider.getBlock("latest")).timestamp,
        5
      );
    });

    it("Should allow multiple deposits for the same user and token", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      expect(await tokenVault.balances(user1.address)).to.equal(DEPOSIT_AMOUNT+DEPOSIT_AMOUNT);
    });
  });

  describe("Withdrawals", function () {
    beforeEach(async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
    });

    it("Should allow withdrawals", async function () {
      await expect(tokenVault.connect(user1).withdraw(DEPOSIT_AMOUNT))
        .to.emit(tokenVault, "Withdrawal")
        .withArgs(user1.address, DEPOSIT_AMOUNT);

      expect(await tokenVault.balances(user1.address)).to.equal(0);
    });

    it("Should reject withdrawals exceeding balance", async function () {
      await expect(tokenVault.connect(user1).withdraw(DEPOSIT_AMOUNT+DEPOSIT_AMOUNT))
        .to.be.revertedWith("Insufficient balance");
    });

    it("Should reject withdrawals of zero amount", async function () {
      await expect(tokenVault.connect(user1).withdraw(0))
        .to.be.revertedWith("Amount must be greater than 0");
    });

    it("Should update proof of life on withdrawal", async function () {
      await tokenVault.connect(user1).withdraw(DEPOSIT_AMOUNT);
      const lastProofOfLife = await tokenVault.lastProofOfLife(user1.address);
      expect(lastProofOfLife).to.be.closeTo(
        (await ethers.provider.getBlock("latest")).timestamp,
        5
      );
    });
  });

  describe("Proof of Life", function () {
    it("Should allow manual proof of life update", async function () {
        const tx = await tokenVault.connect(user1).updateProofOfLife();
        const receipt = await tx.wait();
        const block = await ethers.provider.getBlock(receipt.blockNumber);
        
        await expect(tx)
          .to.emit(tokenVault, "ProofOfLifeUpdated")
          .withArgs(user1.address, (timestamp) => {
            expect(timestamp).to.be.closeTo(block.timestamp, 2); // Improve
            return true;
          });
      });

    it("Should update proof of life on deposit", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      const lastProofOfLife = await tokenVault.lastProofOfLife(user1.address);
      expect(lastProofOfLife).to.be.closeTo(
        (await ethers.provider.getBlock("latest")).timestamp,
        5
      );
    });

    it("Should update proof of life on withdrawal", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).withdraw(DEPOSIT_AMOUNT);
      const lastProofOfLife = await tokenVault.lastProofOfLife(user1.address);
      expect(lastProofOfLife).to.be.closeTo(
        (await ethers.provider.getBlock("latest")).timestamp,
        5
      );
    });
  });

  describe("Fallback Wallet and Period", function () {
    it("Should allow setting fallback wallet", async function () {
      await expect(tokenVault.connect(user1).setFallbackWallet(fallbackWallet.address))
        .to.emit(tokenVault, "FallbackWalletSet")
        .withArgs(user1.address, fallbackWallet.address);

      expect(await tokenVault.fallbackWallets(user1.address)).to.equal(fallbackWallet.address);
    });

    it("Should allow setting user fallback period", async function () {
      await expect(tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD))
        .to.emit(tokenVault, "UserFallbackPeriodSet")
        .withArgs(user1.address, MIN_FALLBACK_PERIOD);

      expect(await tokenVault.userFallbackPeriods(user1.address)).to.equal(MIN_FALLBACK_PERIOD);
    });

    it("Should reject fallback period shorter than minimum", async function () {
      await expect(tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD - 1))
        .to.be.revertedWith("Period too short");
    });

    it("Should reject fallback period longer than maximum", async function () {
      await expect(tokenVault.connect(user1).setUserFallbackPeriod(MAX_FALLBACK_PERIOD + 1))
        .to.be.revertedWith("Period too long");
    });

    it("Should allow any wallet to initiate fallback withdrawal, but send funds to fallback wallet", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).setFallbackWallet(fallbackWallet.address);
      await tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
      await ethers.provider.send("evm_increaseTime", [MIN_FALLBACK_PERIOD]);
      await ethers.provider.send("evm_mine");

      const fallbackWalletInitialBalance = await ERC20Token.balanceOf(fallbackWallet.address);

      await expect(tokenVault.connect(user2).fallbackWithdraw(user1.address, DEPOSIT_AMOUNT))
        .to.emit(tokenVault, "FallbackWithdrawal")
        .withArgs(user1.address, fallbackWallet.address, DEPOSIT_AMOUNT);

      expect(await tokenVault.balances(user1.address)).to.equal(0);
      expect(await ERC20Token.balanceOf(fallbackWallet.address)).to.equal(fallbackWalletInitialBalance + DEPOSIT_AMOUNT);
    });

    it("Should use user's address as fallback if no fallback wallet is set", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
      await ethers.provider.send("evm_increaseTime", [MIN_FALLBACK_PERIOD]);
      await ethers.provider.send("evm_mine");

      const user1InitialBalance = await ERC20Token.balanceOf(user1.address);

      await expect(tokenVault.connect(user2).fallbackWithdraw(user1.address, DEPOSIT_AMOUNT))
        .to.emit(tokenVault, "FallbackWithdrawal")
        .withArgs(user1.address, user1.address, DEPOSIT_AMOUNT);

      expect(await tokenVault.balances(user1.address)).to.equal(0);
      expect(await ERC20Token.balanceOf(user1.address)).to.equal(user1InitialBalance + DEPOSIT_AMOUNT);
    });

    it("Should reset fallback period on new deposit", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).setFallbackWallet(fallbackWallet.address);
      await tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD);
      await ethers.provider.send("evm_increaseTime", [MIN_FALLBACK_PERIOD - 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");

      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);

      await expect(tokenVault.connect(fallbackWallet).fallbackWithdraw(user1.address, DEPOSIT_AMOUNT))
        .to.be.revertedWith("Fallback period not elapsed");
    });

    it("Should not allow fallback withdrawal before period", async function () {
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      await tokenVault.connect(user1).setFallbackWallet(fallbackWallet.address);
      await tokenVault.connect(user1).setUserFallbackPeriod(MIN_FALLBACK_PERIOD);

      // Increase time, but not enough to reach the fallback period
      await ethers.provider.send("evm_increaseTime", [MIN_FALLBACK_PERIOD - 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");

      await expect(
        tokenVault.connect(user2).fallbackWithdraw(user1.address, DEPOSIT_AMOUNT)
      ).to.be.revertedWith("Fallback period not elapsed");

      // Verify that the balance hasn't changed
      expect(await tokenVault.balances(user1.address)).to.equal(DEPOSIT_AMOUNT);
    });
  });

  describe("Owner functions", function () {
    it("Should allow owner to pause the contract", async function () {
      await expect(tokenVault.connect(owner).pause())
        .to.emit(tokenVault, "Paused")
        .withArgs(owner.address);
      
      expect(await tokenVault.paused()).to.be.true;
    });

    it("Should allow owner to unpause the contract", async function () {
      // First, pause the contract
      await tokenVault.connect(owner).pause();
      
      await expect(tokenVault.connect(owner).unpause())
        .to.emit(tokenVault, "Unpaused")
        .withArgs(owner.address);
      
      expect(await tokenVault.paused()).to.be.false;
    });

    it("Should not allow non-owner to pause the contract", async function () {
      await expect(tokenVault.connect(user1).pause())
        .to.be.revertedWithCustomError(tokenVault, "OwnableUnauthorizedAccount")
        .withArgs(user1.address);
    });

    it("Should not allow non-owner to unpause the contract", async function () {
      // First, pause the contract as owner
      await tokenVault.connect(owner).pause();
      
      await expect(tokenVault.connect(user1).unpause())
        .to.be.revertedWithCustomError(tokenVault, "OwnableUnauthorizedAccount")
        .withArgs(user1.address);
    });

    it("Should prevent deposits when paused", async function () {
      await tokenVault.connect(owner).pause();
      
      await expect(tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT))
        .to.be.revertedWithCustomError(tokenVault, "EnforcedPause");
    });

    it("Should prevent withdrawals when paused", async function () {
      // First, make a deposit
      await tokenVault.connect(user1).deposit(DEPOSIT_AMOUNT);
      
      // Then pause the contract
      await tokenVault.connect(owner).pause();
      
      await expect(tokenVault.connect(user1).withdraw(DEPOSIT_AMOUNT))
        .to.be.revertedWithCustomError(tokenVault, "EnforcedPause");
    });
  });
});