import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Prediction Market Test.", function () {
	async function deployFixture() {
		const [deployer, otherAccount] = await ethers.getSigners();
		
		const ERC20 = await ethers.getContractFactory("Sample20");
		const erc20 = await ERC20.deploy(20000000000000);

		const Oracle = await ethers.getContractFactory("OracleMock");
		const oracle = await Oracle.deploy();

		const PMFactory = await ethers.getContractFactory("PMTFactory");
		const pmf = await PMFactory.deploy();

		const OptionMarket = await ethers.getContractFactory("OptionMarket");
		const om = await OptionMarket.deploy();

		return { erc20, pmf, oracle, om, deployer, otherAccount };
	}

	it("Should deploy the contracts correctly", async function () {
		const { erc20, oracle, pmf } = await loadFixture(deployFixture);
		
		// コントラクトのデプロイが成功したか確認
		expect(await erc20.name()).to.equal("TEST");
		expect(await erc20.symbol()).to.equal("test");
		const allMarkets = await pmf.getAllMarkets();
		expect(allMarkets.length).to.equal(0);
	});

	it("Adding initial liquidity and minting OptionToken", async function () {
		const { erc20, oracle, pmf, om, deployer } = await loadFixture(deployFixture);
		const oracleAddr = await oracle.getAddress();
		const collateralAddr = await erc20.getAddress();
		// console.log(oracleAddr, collateralAddr)

		await pmf.createMarket(
			"Presidential Election Winner 2024",
			2,
			collateralAddr,
			oracleAddr,
			3,
			1704067200,
			1710662400,
			["Yes","No"]
		)

		const initLPAmount = 100
		const buyAmount = 20
		
		const marketId = await pmf.getAllMarkets();
		expect(await erc20.balanceOf(deployer)).to.eq(20000000000000)
		await erc20.approve(marketId[0], initLPAmount)

		// 取得したマーケットアドレスを使ってPMコントラクトインスタンスを作成
		// 初期流動性を追加するために、deployerアカウントで実行	
		const market = await ethers.getContractAt("PMT", marketId[0]);
		expect(await market.owner()).to.equal(deployer.address);
		console.log(await market.getQuestion());

		// 初期流動性のバランスチェック
		await market.addInitLiqidity(initLPAmount);
		expect(await market.getBalanceOfOptionPool(1)).to.eq(initLPAmount);
		expect(await market.getBalanceOfOptionPool(2)).to.eq(initLPAmount);
		// オプショントークン保有者情報チェック
		expect(await market.balanceOfUserOption(deployer.address, 1)).to.eq(initLPAmount);
		expect(await market.balanceOfUserOption(deployer.address, 2)).to.eq(initLPAmount);

		// exchange test
		console.log("market is: ", await market.getAddress());
		console.log("om is: ", await om.getAddress());
		await market.setApprovalForAll(await om.getAddress(), true);
		await market.setApprovalForAll(await market.getAddress(), true);
		console.log("Approval for all:", await market.isApprovedForAll(deployer.address, await om.getAddress()));
		console.log("Approval for all:", await market.isApprovedForAll(deployer.address, await market.getAddress()));

		let dy = await om.calculateOptionChange(await market.getAddress(), 1, buyAmount, true);
		console.log(dy)
		await om.buyOption(await market.getAddress(), 1, buyAmount)
		// console.log(await market.getBalanceOfOptionPool(1))
		// console.log(await market.getBalanceOfOptionPool(2))
		expect(await market.balanceOfUserOption(deployer.address, 1)).to.eq(dy[0]);
		expect(await market.balanceOfUserOption(deployer.address, 2)).to.eq(initLPAmount);

		await om.sellOption(await market.getAddress(), 1, buyAmount)
		// console.log(await market.getBalanceOfOptionPool(1))
		// console.log(await market.getBalanceOfOptionPool(2))
		// expect(await market.balanceOfUserOption(deployer.address, 1)).to.eq(initLPAmount);
		// expect(await market.balanceOfUserOption(deployer.address, 2)).to.eq(initLPAmount);
	});
	
})


