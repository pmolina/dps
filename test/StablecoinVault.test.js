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
    // Tests for deployment will go here
  });

  describe("Deposits", function () {
    // Tests for deposits will go here
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