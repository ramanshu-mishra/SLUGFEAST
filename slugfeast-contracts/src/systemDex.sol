// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./pool.sol";

// dex will be used to trade assets using automated market amkers (bounding curve);
// virtual liquidity will be provided 
interface ISlugDex {

    using SafeERC20 for IERC20;

    error TransactionFailure(indexed address token, bool buy, uint256 VETH, uint256 tokens);
    error VETH_Underflow(indexed token);

    event TokenBought(indexed address token, uint256 VETH, uint256 amount);
    event TokenSold(indexed address token, uint256 VETH, uint256 amount);
    
    

    function buy(address token) external payble;
    
    function sell(address token) external public;

    function getSlugFee() external view returns (uint256);

    function setSlugFee(uint256 fee) external;

    function getTokenQuote(address token) external returns (uint256);

    function getETHQuote(address token) external returns (uint256);

    function getTokens(address token, uint256 _VETHs) internal view returns (uint256);

    function getVETH(address token, uint256 _tokens) internal view returns (uint256);

    function calculateFee() internal view returns (uint256);

    function createToken(string memory name, string memory symbol, string memory metadata_uri) external;
}

contract SlugDex is Ownable, Pool, ISlugDex{
     uint256 slugFee;

     constructor() Ownable(msg.sender){
        slugFee = 0;
    }

    function getSlugFee() public view returns (uint256){
        return slugFee;
    }

    function setSlugFee(uint256 fee) public onlyOwner {
        // fee needs to premultiplied by 100 by client for precision upto 2 decimal places;
        slugFee = fee;
    }
    
    function buy (address token) public payable exists(token){
        uint256 gotETH = msg.value;
        uint256 fee = calculateFee(gotETH);
        gotETH -= fee;
        uint256 tokens = getTokens(gotETH);

        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        IERC20 _token = IERC20(token);

        if(tokens > tokenSupply){
            uint256 requiredETH = getVETH(tokenSupply);
            uint256 fee = calculateFee(requiredETH);
            uint256 remainingETH = gotETH - (requiredETH + fee);
            
              
            supply memory newTokenPool = supply({
                _tokenSupply : 0,
                _VETH : VETHSupply + requiredETH
            });

            pools[token] = newTokenPool;

            (bool success ,  ) = owner.call(){valur : fee}("");
             if(!success) revert TransactionFailure(token, true, gotETH, 0);
            (bool success2, ) = (msg.sender).call{value : remainingETH}("");
            if(!success2)revert TransactionFailure(token, true, gotETH, 0);

            
            SafeERC20.safeTransfer(_token, msg.sender, tokenSupply);
            

            emit TokenBought(token, requiredETH+fee, tokenSupply);
            // before emiting token Graduated logic I need to call DEX contract to list this token with remaining 20% of tokens and all of the held ETH in tokenPool
            emit tokenGraduated(token);
        }
        else{
             
            supply memory newTokenPool =  supply({
                _tokenSupply : tokenSupply - tokens,
                _VETH : VETHSupply + gotETH
            });
            pools[token]= newTokenPool;

            (bool success, ) = owner().call{value: fee}("");
            if(!success)revert TransactionFailure(token, true, gotETH, 0);
            SafeERC20.safeTransfer(_token, msg.sender, tokens );

            emit TokenBought(token, gotETH+fee, tokens );
        }
    } 

    function sell(address token, uint256 amount) external exists (token){
        IERC20 _token = IERC20(token);
        require(_token.allowance(msg.sender, address(this)) >= amount, "SLUGFEAST : FORBIDDEN");
        uint256 VETH = getVETH(amount);
        supply memory tokenPool = pools[token];

        supply memory newTokenPool = supply({
            _tokenSupply : tokenPool._tokenSupply + amount,
            _VETH : tokenPool._VETH - VETH
        });

        if(newTokenPool._VETH < 0)revert VETH_Underflow(token); // if at anypoint this error occurs this means there is something wrong with the contract buy/sell logic.

        pools[token] = newTokenPool;
        (bool success, ) = (msg.sender).call({value : VETH})("");
        if(!success) revert TransactionFailure(token, false, 0, token);
        SafeERC20.safeTransferFrom(msg.sender, address(this), amount);
        
        emit TokenSold(token, VETH, token);
    }

    function getTokenQuote(address token)public view exists(token) returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 VETHSupply = tokenPool._VETH;

        uint256 tokenQuote = getK()/(VETHSupply);

        return tokenQuote;
    }

    // actual ETH is getting paid so I did'nt namedit getVETHQuote
    function getETHQuote(address token) public view exists(token) returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;

        uint256 VETHQuote = getK()/(tokenSupply);

        return VETHQuote;
    }

    function getTokens(address token, uint256 _VETH) internal view returns (uint256){
        supply memory tokenPool = pool[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        uint256 k = getK();

        uint256 tokens = tokenSupply - (k/(VETHSupply + _VETH));
        return tokens;
    }

    function getVETH(address token, uint256 _tokens) internal view returns (uint256){
        supply memory tokenPool = pool[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        uint256 k = getK();

        uint256 VETHs = VETHSupply - (k/(tokenSupply + _tokens));
        return VETHs;
    }

    function calculateFee(uint256 ETH) internal view returns (uint256){
        // Fee would be atmax upto 2 decimal places;
        // hance fee would already be multiplied by 100;
        uint256 pfee = slugFee;
        return (ETH*pfee)/10000;
    }


    function createToken(string memory name, string memory symbol, string metadata_uri) external {
        // deploy the custom token with given metadata and mint 1billion tokens to DEX contract, out of which DEX will hold 200 million and 80% tokens will go to the virtual liquidity pool.
        // after this revoke ownership of contract 
    }
}





