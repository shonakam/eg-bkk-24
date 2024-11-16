// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./interface/IPMT.sol";
import "hardhat/console.sol";


contract OptionMarket {
	uint256 constant SCALE = 10**18;

	mapping(address => bool) isTransactionActive;
	mapping(address => mapping(address => uint256)) safeRedeem;

	function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        // Handle the token transfer
        return this.onERC1155Received.selector;
    }

	// CPMMを使用して動的価格を算出
	function calculateOptionChange(
		address target, 
		uint256 opt, 
		uint256 dx, 
		bool isBuy
	) public view returns (uint256 dy, uint256 newCollateralBalance, uint256 newOptionBalance) {
		IPMT t = IPMT(target);
		require(opt < t.getOptions().length, "Invalid option selected");
		require(dx > 0, "Deposit amount must be greater than zero");

		uint256 collateralBalanceBefore = t.getBalanceOfCollateralPool();
		uint256 optionBalanceBefore = t.getBalanceOfOptionPool(opt);
		
		uint256 k = collateralBalanceBefore * optionBalanceBefore;
		uint256 collateralAfter;
		uint256 optionBalanceAfter;

		if (isBuy) {
			collateralAfter = collateralBalanceBefore + dx;
			optionBalanceAfter = k / collateralAfter;
			dy = optionBalanceBefore - optionBalanceAfter;
		} else {
			require(dx <= optionBalanceBefore, "Insufficient options in pool");

			optionBalanceAfter = optionBalanceBefore + dx;
			
			uint256 temp = k / optionBalanceAfter;
			uint256 remainder = k % optionBalanceAfter;
			uint256 roundValue = (2 * remainder >= optionBalanceAfter) ? (temp + 1) : temp;
			collateralAfter = roundValue;

			dy = collateralBalanceBefore - collateralAfter;
		}
		return (dy, collateralAfter, optionBalanceAfter);
	}

    function _adjustOption(
        address target, 
        uint256 opt, 
        uint256 dx, 
        bool isBuy
    ) internal returns (uint256 dy) {
        IPMT t = IPMT(target);
        require(opt < t.getOptions().length, "Invalid option selected");
        require(dx > 0, "Deposit amount must be greater than zero");
        
		uint256 collateralBalanceBefore = t.getBalanceOfCollateralPool();
		uint256 optionBalanceBefore = t.getBalanceOfOptionPool(opt);

		uint256 k = collateralBalanceBefore * optionBalanceBefore;
		uint256 collateralAfter;
		uint256 optionBalanceAfter;

		if (isBuy) {
			require(t.getUserCollateralDeposits(msg.sender) == dx, "Deposit amount does not match.");

			collateralAfter = collateralBalanceBefore + dx;
			optionBalanceAfter = k / collateralAfter;
			dy = optionBalanceBefore - optionBalanceAfter;

			// t.depositHandler(dx);
			t.setBalanceCollateralPool(collateralAfter);
			t.setBalanceOfOptionPool(opt, optionBalanceAfter);
			t.setUserTokenBalances(msg.sender, opt, dy);
			t.setUserCollateralDeposits(msg.sender, 0);
		} else {
			require(dx <= optionBalanceBefore, "Insufficient options in pool");
			require(t.getUserOptionDeposits(msg.sender, opt) == dx, "Deposit amount does not match.");

			optionBalanceAfter = optionBalanceBefore + dx;

			uint256 temp = k / optionBalanceAfter;
			uint256 remainder = k % optionBalanceAfter;
			uint256 roundValue = (2 * remainder >= optionBalanceAfter) ? (temp + 1) : temp;  // 四捨五入
			collateralAfter = roundValue;

			dy = collateralBalanceBefore - collateralAfter;

			t.setBalanceCollateralPool(collateralAfter);
			t.setBalanceOfOptionPool(opt, optionBalanceAfter);
			t.setUserTokenBalances(msg.sender, opt, dx);
			t.setUserRedeemAmount(msg.sender, dy);
			// t.redeemHandler(dy);
			// t.burnHandler(opt, dx);
    	}
        return dy;
    }

	function buyOption(address target, uint256 opt, uint256 dx) public returns (uint256 acquiredOptions) {
        return _adjustOption(target, opt, dx, true); // isBuy = true
    }

    function sellOption(address target, uint256 opt, uint256 dx) public returns (uint256 acquiredOptions) {
        return _adjustOption(target, opt, dx, false); // isBuy = false
    }
	// 最終的なerc20にerc1155から引き出せるようにdy分approve
	function approveRedeem(address target, uint256 opt) external {
		IPMT t = IPMT(target);
		//  t.getUserRedeemAmount();
		(uint256 dy, , ) = calculateOptionChange(target, opt, t.getUserOptionDeposits(msg.sender, opt), false);
		safeRedeem[target][msg.sender] = dy;
		// t.getUserOptionDeposits(msg.sender, opt);
		require(
            IERC20(t.getCollateralToken()).approve(target, t.getUserRedeemAmount(msg.sender)),
            "Collateral token transfer failed"
		);
	}
	// 引き出しの実行
	function redeemCollateral(address target) external {
		require(safeRedeem[target][msg.sender] > 0, "Not deposited.");
		IPMT t = IPMT(target);
		// require(condition);
		require(
            IERC20(t.getCollateralToken()).transferFrom(target, msg.sender, safeRedeem[target][msg.sender]),
			"Redeem failed."
		);
		safeRedeem[target][msg.sender] = 0;
		t.setUserRedeemAmount(msg.sender, 0);
	}
}
