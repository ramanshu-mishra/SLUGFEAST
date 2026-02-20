// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./interfaces/Ipool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// this contract will be used to create virtual liquidity pools for tokens agains 4 virtual ETH. 
// this contract will be called only by dex



struct supply{
    uint256 _tokenSupply;
    uint256 _VETH;
}

abstract contract Pool is IPool, Ownable{
    // tokensupply to VETH supply mapping
    // initially 1 billion token against 4 VETH

    mapping(address => supply) pools;
    mapping(address=>uint256) storedETH;
    mapping(address => uint256)locked_tokens;
    mapping(address=>bool)graduated;
   
    
    modifier notexists(address token) {
        require(pools[token]._tokenSupply != 0 && pools[token]._VETH != 0, "SLUGFEAST : FORBIDDEN");
        _;
    }

    modifier exists(address token){
        require(pools[token]._tokenSupply > 0 || pools[token]._VETH > 0 , "SLUGFEAST : FORBIDDEN");
        _;
    }

    modifier notGraduated(address token) {
        require(!graduated[token], "SLUGFEAST: Token already graduated");
        _;
    }


    constructor() Ownable(msg.sender){}

    function createPool(address token) internal notexists(token){
        uint256 tokenSupply = getInitialTokenSupply();
        uint256 VETHSupply = getInitialVEthSupply();
        pools[token] =  supply({
            _tokenSupply : tokenSupply,
            _VETH : VETHSupply
        });
        
        emit poolcreated(token);
    }



    function getTokenReserves(address token) public view exists(token) returns (uint256) {
        return pools[token]._tokenSupply;
    }

    function getVEthReserves(address token) public view exists(token) returns (uint256) {
        return pools[token]._VETH;
    }

    function getInitialTokenSupply() public pure returns (uint256){
        return 800000000*1000000; //as only 80% are available to trade in slugfeast rest is locked to create LP
    }

    function getInitialVEthSupply() public pure returns (uint256){
        return 4*1000000000000000000;
    }

    function getK() public pure returns (uint256){
        return getInitialTokenSupply()*getInitialVEthSupply();
    }

    function isGraduated(address token) public view returns (bool){

        return graduated[token];
    }

    function getLockedTokens(address token) public view returns (uint256){
        return locked_tokens[token];
    }

    function getStoredETH(address token) public view returns (uint256){
        return storedETH[token];
    }

    function getPoolSupply(address token) external view exists(token) returns (supply memory){
        return pools[token]; 
    }

}



