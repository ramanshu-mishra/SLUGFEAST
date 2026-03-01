// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolInitializer_v4} from "v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./utilities/feecollector.sol";
import "./pool.sol";
import "./slugToken.sol";
import "./interfaces/IsystemDex.sol";
import {console} from "lib/forge-std/src/console.sol";

// dex will be used to trade assets using automated market amkers (bounding curve);
// virtual liquidity will be provided 


//if token is graduated we would need to fetch the slugfee from dex directly instead of fetching it from the contract to avoid extra gas fee. 
// so whenever a token graduated we would need to maintain an offchain database for it ass well, and we should not allow anybody to check the price of token through contract once graduated.


contract SlugDex is  ISlugDex, Pool , feeCollector, ReentrancyGuard{
    using SafeERC20 for IERC20;
     uint256 slugFee;
     IPoolManager private _poolManager;
     IPositionManager private _positionManager;
     uint24 private constant _POOL_FEE = 1500; // 0.30% fee tier
     int24 private constant _TICK_SPACING = 30; // tick spacing for 0.30% fee
     mapping(address => uint256)nonce_map;


    modifier verifySignature(uint256 nonce, bytes memory _signature)
    {   
        require(_signature.length == 65, "SLUGFEAST: INVALID SIGNATURE LENGTH");

    // 1. Recreate the original data hash
    bytes32 dataHash = keccak256(abi.encodePacked(msg.sender, nonce));
    
    // 2. Wrap it in the Ethereum Signed Message prefix
    bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));

    bytes32 r;
    bytes32 s;
    uint8 v;

    // 3. Extract r, s, v
    assembly {
        r := mload(add(_signature, 32))
        s := mload(add(_signature, 64))
        v := byte(0, mload(add(_signature, 96)))
    }

    // 4. Correct for EIP-155 (v should be 27 or 28)
    if (v < 27) v += 27;

    address signer = ecrecover(messageHash, v, r, s);
    require(owner() == signer, "SLUGFEAST: UNAUTHORIZED ACCESS");
    _;
        
    }

    modifier checkReplay(uint256 nonce){
        require(nonce_map[msg.sender] != nonce, "SLUGFEAST: FAILED DUE TO REPLAY");
        nonce_map[msg.sender]++;
        _;   
    }
    


     constructor( uint256 _slugFee, address poolManager_, address positionManager_) 
     {
        slugFee = _slugFee;
        _poolManager = IPoolManager(poolManager_);
        _positionManager = IPositionManager(positionManager_);
    }



    function getSlugFee() public view returns (uint256){
        return slugFee;
    }


    function getNonce() public view returns (uint256){
        return nonce_map[msg.sender];
    }



    function setSlugFee(uint256 fee) public onlyOwner {
        // fee needs to premultiplied by 100 by client for precision upto 2 decimal places;
        slugFee = fee;
    }

    function getPoolManager() public view returns (address){
        return address(_poolManager);
    }

    function getPositionManager() public view returns (address){
        return address(_positionManager);
    }

    function getPoolFee() public pure returns (uint24){
        return _POOL_FEE;
    }

    function getTickSpacing() public pure returns (int24){
        return _TICK_SPACING;
    }



    function buy (address token, uint256 nonce) external payable exists(token) checkReplay(nonce) notGraduated(token) nonReentrant {
       
        uint256 gotETH = msg.value;
        if(gotETH < 10000) revert TooSmallTransaction(token, gotETH);

        uint256 fee = calculateFee(gotETH);
             
        uint256 tokens = getTokens(token,gotETH-fee);
        
        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        IERC20 _token = IERC20(token);
        
       

        if(tokens > tokenSupply){
            uint256 requiredETH = getVETH(token, tokenSupply);
            uint256 fee_special = calculateFee(requiredETH);
            takeFee(fee_special);
            uint256 remainingETH = gotETH - (requiredETH + fee_special);
            storedETH[token] += requiredETH;
              
            supply memory newTokenPool = supply({
                _tokenSupply : 0,
                _VETH : VETHSupply + requiredETH
            });

            pools[token] = newTokenPool;

            
            (bool success2, ) = (msg.sender).call{value : remainingETH}("");
            if(!success2)revert TransactionFailure(token, true, gotETH, 0);

            
            SafeERC20.safeTransfer(_token, msg.sender, tokenSupply);
            

            emit TokenBought(token, requiredETH+fee_special, tokenSupply);
            // before emiting token Graduated logic I need to call DEX contract to list this token with remaining 20% of tokens and all of the held ETH in tokenPool
        }
        else{
             gotETH -= fee;
             takeFee(fee);//storing fee in the contract itself
             storedETH[token] += gotETH;
            supply memory newTokenPool =  supply({
                _tokenSupply : tokenSupply - tokens,
                _VETH : VETHSupply + gotETH
            });
            pools[token]= newTokenPool;

           
            SafeERC20.safeTransfer(_token, msg.sender, tokens );

            emit TokenBought(token, gotETH+fee, tokens );
        }
         supply memory pool = pools[token];


         // this function will deploy the token to external DEX and the token will be available to trade outside SLUGFEAST platform
         if(pool._tokenSupply == 0){
            graduateToken(token);
            graduated[token]=true; 
            emit tokenGraduated(token);
         }
    } 



    function sell(address token, uint256 amount, uint256 nonce) external exists(token) notGraduated(token) checkReplay(nonce) nonReentrant {
        
        IERC20 _token = IERC20(token);
        require(_token.allowance(msg.sender, address(this)) >= amount, "SLUGFEAST : FORBIDDEN");
        uint256 VETH = getVETH(token, amount);
        uint256 fee = calculateFee(VETH);
        storedETH[token] -= VETH;

        takeFee(fee);
        supply memory tokenPool = pools[token];


        supply memory newTokenPool = supply({
            _tokenSupply : tokenPool._tokenSupply + amount,
            _VETH : tokenPool._VETH - VETH
        });

        

        pools[token] = newTokenPool;
        SafeERC20.safeTransferFrom(_token, msg.sender, address(this), amount);
        (bool success, ) = (msg.sender).call{value : VETH-fee}("");
        if(!success) revert TransactionFailure(token, false, 0, amount);
        
        emit TokenSold(token, VETH, amount);
    }


    // gives the amount of token recieved in 1 VETH
    function getTokenQuote(address token)public view exists(token) notGraduated(token) returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 VETHSupply = tokenPool._VETH;

        uint256 tokenQuote = getK()/(VETHSupply);

        return tokenQuote;
    }



    // actual ETH is getting paid so I did'nt namedit getVETHQuote
    // recieved the amount of ETH obtained in 1 token 
    function getETHQuote(address token) public view exists(token) notGraduated(token) returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;

        uint256 VETHQuote = getK()/(tokenSupply);

        return VETHQuote;
    }



    function getTokens(address token, uint256 _VETH) internal view returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        uint256 k = getK();

        uint256 tokens = tokenSupply - (k/(VETHSupply + _VETH));
        return tokens;
    }



    function getVETH(address token, uint256 _tokens) internal view returns (uint256){
        supply memory tokenPool = pools[token];
        uint256 tokenSupply = tokenPool._tokenSupply;
        uint256 VETHSupply = tokenPool._VETH;
        uint256 k = getK();

        uint256 VETHs = VETHSupply - (k/(tokenSupply + _tokens));
        return VETHs;
    }



    function calculateFee(uint256 ETH) public view returns (uint256){
        // Fee would be atmax upto 2 decimal places;
        // hance fee would already be multiplied by 100;
        uint256 pfee = slugFee;
        return (ETH*pfee)/10000; // we need to impose some minimum buying condition in buy function to prevent fee buypass through split buying
        // here if pfee = 0.5 => 50 
    }



    function createToken(string memory name, string memory symbol, string memory metadata_uri, string memory id ,uint256 nonce, bytes memory signature) checkReplay(nonce)   external {
        // deploy the custom token with given metadata and mint 1billion tokens to DEX contract, out of which DEX will hold 200 million and 80% tokens will go to the virtual liquidity pool.
        // after this revoke ownership of contract 

        
        
        slugToken newToken  = new slugToken(name,symbol,metadata_uri);
        address newTokenAddress = address(newToken);

        newToken.mint(address(this), (10**9)*(10**6)); // minted 1 billion tokens
        locked_tokens[newTokenAddress] = 200*(10**6)*(10**6); // locked 200 million tokens
        pools[newTokenAddress] = supply({
            _tokenSupply : 800*(10**6)*(10**6),
            _VETH : 4*(10**18)
        }); // 800 million tokens available to be traded

        createPool(newTokenAddress);
        emit TokenCreated(newTokenAddress, id);
    }



    function graduateToken(address token) internal {
        // Graduate the token from the bonding curve to a Uniswap V4 pool.
        // Uses the locked 200M tokens + all accumulated VETH (real ETH) as liquidity.

        uint256 accumulatedETH = storedETH[token]; // all real ETH collected from trading
        uint256 lockedTokens = locked_tokens[token]; // 200M tokens reserved for LP

        require(lockedTokens > 0, "SLUGFEAST: No locked tokens for graduation");
        require(accumulatedETH > 0, "SLUGFEAST: No ETH for graduation");

        // --- Step 1: Build PoolKey with sorted currencies ---
        // currency0 must have a lower address than currency1
        // Native ETH = address(0), which is always lower than any token address
        Currency currency0 = Currency.wrap(address(0)); // Native ETH
        Currency currency1 = Currency.wrap(token);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: _POOL_FEE,
            tickSpacing: _TICK_SPACING,
            hooks: IHooks(address(0)) // no hooks
        });

        // --- Step 2: Compute sqrtPriceX96 from token reserves ---
        // Price = currency1_amount / currency0_amount = lockedTokens / accumulatedETH
        // sqrtPriceX96 = sqrt(price) * 2^96
        uint160 sqrtPriceX96 = encodeSqrtRatioX96(lockedTokens, accumulatedETH);

        // --- Step 3: Initialize the Uniswap V4 pool ---
        _poolManager.initialize(key, sqrtPriceX96);

        // --- Step 4: Compute tick range (full range for maximum liquidity coverage) ---
        int24 tickLower = (TickMath.MIN_TICK / _TICK_SPACING) * _TICK_SPACING;
        int24 tickUpper = (TickMath.MAX_TICK / _TICK_SPACING) * _TICK_SPACING;

        // --- Step 5: Compute liquidity from token amounts and price range ---
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceLowerX96,
            sqrtPriceUpperX96,
            accumulatedETH,  // amount0 (ETH)
            lockedTokens     // amount1 (token)
        );

        // --- Step 6: Approve token to PositionManager for transfer ---
        IERC20(token).approve(address(_positionManager), lockedTokens);

        // --- Step 7: Encode actions for MINT_POSITION + SETTLE_PAIR + SWEEP ---
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](3);
        // MINT_POSITION params: poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            uint256(liquidity),
            uint128(accumulatedETH),  // amount0Max (ETH slippage)
            uint128(lockedTokens),   // amount1Max (token slippage)
            address(this),           // LP NFT owner = this contract (liquidity is locked)
            bytes("")               // no hook data
        );
        // SETTLE_PAIR params: currency0, currency1
        params[1] = abi.encode(currency0, currency1);
        // SWEEP params: currency, recipient — sweep leftover ETH back to contract
        params[2] = abi.encode(currency0, address(this));

        // --- Step 8: Execute liquidity provision, sending ETH as msg.value ---
        _positionManager.modifyLiquidities{value: accumulatedETH}(
            abi.encode(actions, params),
            block.timestamp + 300 // 5 minute deadline
        );

        // --- Step 9: Clear locked tokens and pool state ---
        locked_tokens[token] = 0;
        


        emit tokenDeployed(token);
    }



    function encodeSqrtRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160 sqrtPriceX96) {
        require(amount0 > 0, "PriceMath: division by zero");
        // Multiply amount1 by 2^192 (left shift by 192) to preserve precision after the square root.
        // As fas as I've seen uniswap requires startingprice to be in this format (P^1/2)*(2*96) where P = token1supply/token0Supply
        uint256 ratioX192 = (amount1 << 192) / amount0;
        uint256 sqrtRatio = Math.sqrt(ratioX192);
        require(sqrtRatio <= type(uint160).max, "PriceMath: sqrt overflow");
        sqrtPriceX96 = uint160(sqrtRatio);
    }



    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
    // Allow the contract to receive ETH (e.g. swept ETH from PositionManager)
    receive() external payable {}


    
    
}





