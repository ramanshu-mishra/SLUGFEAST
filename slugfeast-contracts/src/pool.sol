// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./systemDex.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// this contract will be used to create virtual liquidity pools for tokens agains 4 virtual ETH. 
// this contract will be called only by dex
interface IPool {

    event poolcreated(indexed address tokenA);
    event tokenGraduated(indexed address token);
    event tokenDeployed(indexed address token);

    function createPool(address tokenA, uint256 virtualETH) internal;

    function getTokenReserves(address token) external;

    function getVEthReserves(address token) external;

    
    
}


struct supply{
    uint256 _tokenSupply;
    uint256 _VETH;
}

contract Pool is IPool{
    // tokensupply to VETH supply mapping
    // initially 1 billion token against 4 VETH

    mapping(address => supply) pools;
    mapping(address => uint256)locked_tokens;
   
    
    modifier notexists(address token) {
        require(pools[token]._tokenSupply != 0 && pools[token]._VETH != 0, "SLUGFEAST : FORBIDDEN");
        _;
    }

    modifier exists(address token){
        require(pools[token]._tokenSupply > 0 || pools[token]._VETH > 0 , "SLUGFEAST : FORBIDDEN");
    }

    function createPool(address token, uint256 virtualETH) onlyOwner notexists(token){
        uint256 tokenSupply = getInitialTokenSupply();
        uint256 VETHSupply = getInitialVETHSupply();
        pools[token] =  supply({
            _tokenSupply : tokenSupply,
            _VETH : VETHSupply
        });

        emit poolcreated(token);
    }



    function getTokenReserves(address token) public view returns (uint256) exists(token){
        return pools[token]._tokenSupply;
    }

    function getVEthReserves(address token) public view returns (uint256) exists(token){
        return pools[token]._VETH;
    }

    function getInitialTokenSupply() public view returns (uint256){
        return 800000000*1000000;
    }

    function getInitialVEthSupply() public view returns (uint256){
        return 4*1000000000000000000;
    }

    function getK() public view returns (uint256){
        return getInitialTokenSupply()*getInitialVETHSupply();
    }

    

}


