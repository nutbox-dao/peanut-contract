# Peanut contracts(Nutbox v1)

## About Peanut

Peanut (e.g. Nutbox v1) is a staking platform build on top of PoS chains, and PNUT is the community token of Peanut network. On Peanut network people can:
 - Stake specific asset and got PNUT as staking reward. 
 - Provide liquidity like PNUT-TRX and mint with the lptoken.
 - Wrap STEEM to trc20 token TSTEEM or SBD to trc20 token TSBD.

Visit our [homepage](https://nutbot.io/) to join the staking game or check our whitepaper [here](https://docs.nutbox.io/lite_paper_v1/) for more details

## Contract Address

Peanut contains serial contracts which currently deployed on Tron.

### NutboxSteem

NutboxSteem contract is the implementation that wrap STEEM to TSTEEM.
With our steem bridge, people can also redeem their TSTEEM back to STEEM.

See [here](https://tronscan.org/#/contract/TBUZYrDh7gzjd1PLnkMHWoAo55ctRzZzGN) for contract information.

### NutboxSbd

NutboxSBD contract is the implementation that wrap SBD to TSBD.
With our steem bridge, people can also redeem their TSBD back to SBD.

See [here](https://tronscan.org/#/contract/TEPZJmYLJxJc8b5FueswwLWmUDhJGnih6Q) for contract information.

### NutboxPnut

NutboxPnut is core contract of Peanut network. People delegate SP into the pool, and got reward at each block. The beginning reward of each block to all of the delegaters is 20 PNUTs, and would decrease to specific amount at a pre setted block height.

See [here](https://tronscan.org/#/contract/TPZddNpQJHu8UtKPY1PYDBv2J5p5QpJ6XW) for contract information.





