const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StablecoinVault", function () {
  let StablecoinVault, stablecoinVault, owner, user1, user2, fallbackWallet;
  let USDC, USDT, DAI;

  const INITIAL_SUPPLY = ethers.parseUnits("1000000", 18); // 1 million tokens
  const DEPOSIT_AMOUNT = ethers.parseUnits("1000", 18); // 1000 tokens
  const MIN_FALLBACK_PERIOD = 90 * 24 * 60 * 60; // 90 days in seconds
  const MAX_FALLBACK_PERIOD = 1095 * 24 * 60 * 60; // 3 years in seconds

  beforeEach(async function () {
    [owner, user1, user2, fallbackWallet] = await ethers.getSigners();

    // Deploy mock USDC, USDT, and DAI
    const MockToken = await ethers.getContractFactory("MockERC20");
    USDC = await MockToken.deploy("USD Coin", "USDC", 6);
    USDT = await MockToken.deploy("Tether", "USDT", 6);
    DAI = await MockToken.deploy("Dai Stablecoin", "DAI", 18);

    await USDC.mint(user1.address, INITIAL_SUPPLY);
    await USDT.mint(user1.address, INITIAL_SUPPLY);
    await DAI.mint(user1.address, INITIAL_SUPPLY);

    // Deploy StablecoinVault
    StablecoinVault = await ethers.getContractFactory("StablecoinVault");
    stablecoinVault = await StablecoinVault.deploy(
      await USDC.getAddress(),
      await USDT.getAddress(),
      await DAI.getAddress(),
      owner.address
    );

    // Approve StablecoinVault to spend tokens
    await USDC.connect(user1).approve(await stablecoinVault.getAddress(), INITIAL_SUPPLY);
    await USDT.connect(user1).approve(await stablecoinVault.getAddress(), INITIAL_SUPPLY);
    await DAI.connect(user1).approve(await stablecoinVault.getAddress(), INITIAL_SUPPLY);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await stablecoinVault.owner()).to.equal(owner.address);
    });

    it("Should set the correct token addresses", async function () {
      expect(await stablecoinVault.USDC()).to.equal(await USDC.getAddress());
      expect(await stablecoinVault.USDT()).to.equal(await USDT.getAddress());
      expect(await stablecoinVault.DAI()).to.equal(await DAI.getAddress());
    });

    it("Should initialize with correct fallback period constants", async function () {
      const minFallbackPeriod = await stablecoinVault.MIN_FALLBACK_PERIOD();
      const maxFallbackPeriod = await stablecoinVault.MAX_FALLBACK_PERIOD();
      
      expect(minFallbackPeriod).to.equal(90 * 24 * 60 * 60); // 90 days in seconds
      expect(maxFallbackPeriod).to.equal(1095 * 24 * 60 * 60); // 3 years in seconds
    });

    it("Should not be paused initially", async function () {
      expect(await stablecoinVault.paused()).to.be.false;
    });

    it("Should have zero balance for all tokens initially", async function () {
      const tokens = [USDC, USDT, DAI];
      for (const token of tokens) {
        const balance = await stablecoinVault.getBalance(user1.address, await token.getAddress());
        expect(balance).to.equal(0);
      }
    });

    it("Should not have any fallback wallets set initially", async function () {
      const fallbackWallet = await stablecoinVault.fallbackWallets(user1.address);
      expect(fallbackWallet).to.equal(ethers.ZeroAddress);
    });

    it("Should not have any user fallback periods set initially", async function () {
      const userFallbackPeriod = await stablecoinVault.userFallbackPeriods(user1.address);
      expect(userFallbackPeriod).to.equal(0);
    });
  });

  describe("Deposits", function () {
    it("Should allow deposits of USDC", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.emit(stablecoinVault, "Deposit")
        .withArgs(user1.address, await USDC.getAddress(), DEPOSIT_AMOUNT);

      expect(await stablecoinVault.getBalance(user1.address, await USDC.getAddress())).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should allow deposits of USDT", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await USDT.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.emit(stablecoinVault, "Deposit")
        .withArgs(user1.address, await USDT.getAddress(), DEPOSIT_AMOUNT);

      expect(await stablecoinVault.getBalance(user1.address, await USDT.getAddress())).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should allow deposits of DAI", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await DAI.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.emit(stablecoinVault, "Deposit")
        .withArgs(user1.address, await DAI.getAddress(), DEPOSIT_AMOUNT);

      expect(await stablecoinVault.getBalance(user1.address, await DAI.getAddress())).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should reject deposits of invalid tokens", async function () {
      await expect(stablecoinVault.connect(user1).deposit(ethers.ZeroAddress, DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.be.revertedWith("Invalid token");
    });

    it("Should reject deposits of zero amount", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await USDC.getAddress(), 0, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.be.revertedWith("Amount must be greater than 0");
    });

    it("Should set fallback wallet on first deposit", async function () {
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      expect(await stablecoinVault.fallbackWallets(user1.address)).to.equal(fallbackWallet.address);
    });

    it("Should set user fallback period on first deposit", async function () {
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      expect(await stablecoinVault.userFallbackPeriods(user1.address)).to.equal(MIN_FALLBACK_PERIOD);
    });

    it("Should reject fallback period shorter than minimum", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD - 1))
        .to.be.revertedWith("Period too short");
    });

    it("Should reject fallback period longer than maximum", async function () {
      await expect(stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MAX_FALLBACK_PERIOD + 1))
        .to.be.revertedWith("Period too long");
    });

    it("Should update proof of life on deposit", async function () {
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      const lastProofOfLife = await stablecoinVault.getLastProofOfLife(user1.address);
      expect(lastProofOfLife).to.be.closeTo(
        (await ethers.provider.getBlock("latest")).timestamp,
        5
      );
    });

    it("Should allow multiple deposits for the same user and token", async function () {
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      expect(await stablecoinVault.getBalance(user1.address, await USDC.getAddress())).to.equal(DEPOSIT_AMOUNT+DEPOSIT_AMOUNT);
    });
  });

  describe("Withdrawals", function () {
    // Tests for withdrawals will go here
  });

  describe("Proof of Life", function () {
    // Tests for proof of life functionality will go here
  });

  describe("Fallback Wallet", function () {
    // Tests for fallback wallet functionality will go here
  });

  describe("Owner functions", function () {
    it("Should allow owner to pause the contract", async function () {
      await expect(stablecoinVault.connect(owner).pause())
        .to.emit(stablecoinVault, "Paused")
        .withArgs(owner.address);
      
      expect(await stablecoinVault.paused()).to.be.true;
    });

    it("Should allow owner to unpause the contract", async function () {
      // First, pause the contract
      await stablecoinVault.connect(owner).pause();
      
      await expect(stablecoinVault.connect(owner).unpause())
        .to.emit(stablecoinVault, "Unpaused")
        .withArgs(owner.address);
      
      expect(await stablecoinVault.paused()).to.be.false;
    });

    it("Should not allow non-owner to pause the contract", async function () {
      await expect(stablecoinVault.connect(user1).pause())
        .to.be.revertedWithCustomError(stablecoinVault, "OwnableUnauthorizedAccount")
        .withArgs(user1.address);
    });

    it("Should not allow non-owner to unpause the contract", async function () {
      // First, pause the contract as owner
      await stablecoinVault.connect(owner).pause();
      
      await expect(stablecoinVault.connect(user1).unpause())
        .to.be.revertedWithCustomError(stablecoinVault, "OwnableUnauthorizedAccount")
        .withArgs(user1.address);
    });

    it("Should prevent deposits when paused", async function () {
      await stablecoinVault.connect(owner).pause();
      
      await expect(stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD))
        .to.be.revertedWithCustomError(stablecoinVault, "EnforcedPause");
    });

    it("Should prevent withdrawals when paused", async function () {
      // First, make a deposit
      await stablecoinVault.connect(user1).deposit(await USDC.getAddress(), DEPOSIT_AMOUNT, fallbackWallet.address, MIN_FALLBACK_PERIOD);
      
      // Then pause the contract
      await stablecoinVault.connect(owner).pause();
      
      await expect(stablecoinVault.connect(user1).withdraw(await USDC.getAddress(), DEPOSIT_AMOUNT))
        .to.be.revertedWithCustomError(stablecoinVault, "EnforcedPause");
    });
  });
});