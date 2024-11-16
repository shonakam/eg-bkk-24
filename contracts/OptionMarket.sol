// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interface/IPMT.sol";
import "hardhat/console.sol";

contract OptionMarket {
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
	) external view returns (uint256 acquiredOptions, uint256 newCollateralBalance, uint256 newOptionBalance) {
		IPMT t = IPMT(target);
		require(opt < t.getOptions().length, "Invalid option selected");
		require(dx > 0, "Deposit amount must be greater than zero");

		uint256 collateralBalanceBefore = t.getBalanceOfCollateralPool();
		uint256 optionBalanceBefore = t.getBalanceOfOptionPool(opt);
		
		require(collateralBalanceBefore > 0 && optionBalanceBefore > 0, "Invalid pool balances");
		
		uint256 k = collateralBalanceBefore * optionBalanceBefore;
		uint256 collateralAfter = isBuy ? collateralBalanceBefore + dx : collateralBalanceBefore - dx;

		// 売却時にdxがコラテラルバランスを超えないことを確認
		if (!isBuy) {
			require(dx <= collateralBalanceBefore, "Insufficient collateral in pool");
		}

		uint256 optionBalanceAfter = k / collateralAfter;
		acquiredOptions = optionBalanceBefore - optionBalanceAfter;
		return (acquiredOptions, collateralAfter, optionBalanceAfter);
	}

    function _adjustOption(
        address target, 
        uint256 opt, 
        uint256 dx, 
        bool isBuy
    ) internal returns (uint256 acquiredOptions) {
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
			acquiredOptions = optionBalanceBefore - optionBalanceAfter;

			t.setBalanceCollateralPool(collateralAfter);
			t.setBalanceOfOptionPool(opt, optionBalanceAfter);

			// オプションをmintして購入者に渡す
			t.mintHandler(opt, acquiredOptions);
			t.setUserTokenBalances(msg.sender, opt, acquiredOptions);

		} else {
			require(dx <= optionBalanceBefore, "Insufficient options in pool");
			require(collateralAfter > 0, "Invalid collateral state after transaction");

			optionBalanceAfter = optionBalanceBefore + dx;
			collateralAfter = k / optionBalanceAfter;
			acquiredOptions = collateralBalanceBefore - collateralAfter;

			t.setBalanceCollateralPool(collateralAfter);
			t.setBalanceOfOptionPool(opt, optionBalanceAfter);

			// オプションを焼却しコラテラルを払い戻す
			t.setUserTokenBalances(msg.sender, opt, dx);
			t.burnHandler(opt, dx);
    	}
        return acquiredOptions;
    }

	function buyOption(address target, uint256 opt, uint256 dx) public returns (uint256 acquiredOptions) {
        return _adjustOption(target, opt, dx, true); // isBuy = true
    }
    function sellOption(address target, uint256 opt, uint256 dx) public returns (uint256 acquiredOptions) {
        return _adjustOption(target, opt, dx, false); // isBuy = false
    }
}
