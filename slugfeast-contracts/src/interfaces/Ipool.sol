// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IPool {

    event poolcreated( address indexed tokenA);
    event tokenGraduated( address indexed token);
    event tokenDeployed(address indexed token);

    function getTokenReserves(address token) external view returns (uint256);

    function getVEthReserves(address token) external view returns (uint256);

    function isGraduated(address token) external view returns (bool);

    function getLockedTokens(address token) external view returns (uint256);

    function getStoredETH(address token) external view returns (uint256);

    
}