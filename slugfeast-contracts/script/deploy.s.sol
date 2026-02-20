// script/DeployDex.s.sol
pragma solidity ^0.8.33;

import "forge-std/Script.sol";
import {SlugDex} from "../src/systemDex.sol";

contract DeployDex is Script {

    uint256 dexFee = 75; //0.75 (multiplied by 100 to handle precision)
    address _poolManager = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address _positionManager = 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D;
    function run() external {
        vm.startBroadcast();

       
        new SlugDex(dexFee, _poolManager, _positionManager); 

        vm.stopBroadcast();
    }
}