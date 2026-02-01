**SLUGFEAST - An Ethereum based meme-coin/token trading platform** 
SLUGFEAST allows anybody to create tokens and trade over it without worrying about liquidity. 

> SLUGFEAST mechanism can be divided into two major parts : 
> 
>  1. Coin Generation 
>  2. Coin Listing

After coin listing the coin can be traded at any decentralized exchange with liquidity provided by SLUGFEAST itself.
**Coin Generation:** Anyone on SLUGFEAST would create a profile using their wallet. They would be able to create a coin anytime by giving a name, symbol and metadata without providing initial liquidity.

***The magic behind zero liquidity token creation/trading*** : SLUGFEAST DEX contract creates virtual liquidity using bonding curve (x*y = k) AMM (Automated Market Maker), by holding all of the incoming ETH and transfering tokens for them. once 80% of the tokens are sold  i.e. total amount of virtual liquidity , the token gets gets into the grauaduation phase.

**Token Graduation**: once all of the tokens into Token-Pool get sold the DEX contracts automatically takes the remaining 20% tokens and the aggregated ETH and lists the token to a Etherium DEX. (presumingly uniswap) (will be decided in the future).

**Protection against Rug Pulls** : it is possible that the token holders who provided initial liquidity pull out their ETH soon after token listing making the token illiquid, so the DEX burns all the LP tokens soon after listing the token to the exchange. 

**Fixed token supply** : the token supply is capped at 1 Billion tokens.

**Virtual liquidity** :  the contract written up untill now takes 4VETH to be the initial amount of virtual Ethereums agains 800 million tokens. (out of the total 1Billion tokens minted ). 
The ownership of contracts needs to be revoked eventually.
***(I havent yet decided/figured out when should the ownership be revoked , soon after token minting or after Listing to DEX)***

**Proposed chains**: Ethereum chain process very few transactions per second, thus deploying to an L2 chain is an obvious solution. I havent yet decided about the chain to deploy on
***I suppose Base or polygon could be one of the possible L2 chains on which SLUGFEAST smart contracts will get deployed.*** 
Base wins over transactions speed and low gas fee, while polygon provides more decentralization due to around 100 times more validators. 




