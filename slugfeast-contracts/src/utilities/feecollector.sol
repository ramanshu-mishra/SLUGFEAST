// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract feeCollector is Ownable{
    uint256 generatedFee = 0;

    constructor(){}

    modifier hasEnoughFee(uint256 amount) {
        require(generatedFee >= amount, "SLUGFEAST: Insufficient balance");
        _;
    }

    function takeFee(uint256 amount) internal {
        generatedFee += amount;
    }

    function getCollectedFee() internal view returns(uint256) {
        return generatedFee;
    }

    function withdrawFee(uint256 amount) external onlyOwner hasEnoughFee(amount){
        address payable ownerAddress  = payable(owner());

        (bool success , ) = ownerAddress.call{value: amount}("");
        require(success, "SLUGFEAST: TRANSACTION FAILURE");
    }
}