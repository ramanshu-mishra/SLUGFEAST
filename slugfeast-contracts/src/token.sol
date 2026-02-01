// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract token is ERC20, Ownable{
    string memory metadata;
    constructor(string memory name, string memory symbol, string memory metadata) Ownable(msg.sender) ERC20(name,symbol){
        mint(pumpAddress, );
    }

    function mint(address addr, uint256 value) public onlyOwner {
        _mint(addr,value);
    }

}
