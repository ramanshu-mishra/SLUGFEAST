// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISlugDex {

    

    error TransactionFailure( address token, bool buy, uint256 VETH, uint256 tokens);
    error VETH_Underflow(address token);
    error TooSmallTransaction(address token, uint256 value);

    event TokenBought( address indexed token, uint256 VETH, uint256 amount);
    event TokenSold( address indexed token, uint256 VETH, uint256 amount);
    event TokenCreated( address indexed token);
    
    

    function buy(address token) external payable;
    
    function sell(address token, uint256 amount) external ;

    function getSlugFee() external view returns (uint256);

    function setSlugFee(uint256 fee) external;

    function getTokenQuote(address token) external returns (uint256);

    function getETHQuote(address token) external returns (uint256);


    function createToken(string memory name, string memory symbol, string memory metadata_uri) external;

    function getPoolManager() external view returns (address);

    function getPositionManager() external view returns (address);

    function getPoolFee() external pure returns (uint24);

    function getTickSpacing() external pure returns (int24);

}