pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface PnutsMining  {
    function transfer(address _to, uint256 _value) external returns (bool success);
    function totalSupply() external view returns (uint256);
    function mint(address _to, uint256 _amount) external;
}

contract PeanutsPool is Ownable {
    using SafeMath for uint256;

    struct Delegator {
        uint256 amount;             // reserved VEST
        uint256 availablePeanuts;   // minted peanuts for user
        uint256 debtRewards;        // rewards debt 
        bool hasDeposited;          // set true when first time deposit
        string steemAccount;        // related steem acount
    }

    mapping(address => Delegator) public delegators;
    address[] public delegatorList;

    PnutsMining Pnuts;
    address public minter;
    uint256 public lastRewardBlock;
    uint256 public shareAcc;
    uint256 public totalDepositedSP;
    uint256 public genesisBlock;
    address public devAddress;
    bool    public initialized;
    
    event Deposit(string steemAccount, address delegator, uint256 amount);
    event Withdraw(string steemAccount, address delegator, uint256 amount);
    event WithdrawPeanuts(string steemAccount, address delegator, uint256 amount);

    modifier onlyDelegator() {
        require(delegators[msg.sender].hasDeposited, "Account is not a delegator");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller is not the minter");
        _;
    }

    constructor (address _punts) public {
        Pnuts = PnutsMining(_punts);
        totalDepositedSP = 0;
        lastRewardBlock = 0;
        shareAcc = 0;
        genesisBlock = block.number;
        devAddress = msg.sender;
        initialized = false;
    }

    // Only minter can call this method
    function deposit(string memory steemAccount, address delegator, uint256 _amount)
        public
        onlyMinter
    {
        require(initialized == true, "Contract has not been initialized");

        if (_amount == 0) return;

        // lastRewardBlock == 0 means there is not delegator exist. When first delegator come,
        // we set lastRewardBlock as current block number, then our game starts!
        if (lastRewardBlock == 0) {
            lastRewardBlock = block.number;
        }

        // Add to delegator list if account hasn't deposited before
        if(!delegators[delegator].hasDeposited) {
            delegators[delegator].hasDeposited = true;
            delegators[delegator].availablePeanuts = 0;
            delegators[delegator].steemAccount = steemAccount;
            delegators[delegator].amount = 0;
            delegators[delegator].debtRewards = 0;
            delegatorList.push(delegator);
        }

        _updateRewardInfo();

        if (delegators[delegator].amount > 0) {
            uint256 pending = delegators[delegator].amount.mul(shareAcc).sub(delegators[delegator].debtRewards);
            if(pending > 0) {
                delegators[delegator].availablePeanuts = delegators[delegator].availablePeanuts.add(pending);
            }
        }

        delegators[delegator].amount = delegators[delegator].amount.add(_amount);
        totalDepositedSP = totalDepositedSP.add(_amount);

        delegators[delegator].debtRewards = delegators[delegator].amount.mul(shareAcc);

        emit Deposit(steemAccount, delegator, _amount);
    }

    // Only minter can call this method
    function withdraw(address delegator, uint256 _amount) 
        public
        onlyMinter
    {
        require(initialized == true, "Contract has not been initialized");

        if (_amount == 0) return;

        if (delegators[delegator].amount == 0) return;

        _updateRewardInfo();

        uint256 pending = delegators[delegator].amount.mul(shareAcc).sub(delegators[delegator].debtRewards);
        if(pending > 0) {
            delegators[delegator].availablePeanuts = delegators[delegator].availablePeanuts.add(pending);
        }
        
        uint256 withdrawAmount;
        if (_amount >= delegators[delegator].amount)
            withdrawAmount = delegators[delegator].amount;
        else
            withdrawAmount = _amount;

        delegators[delegator].amount = delegators[delegator].amount.sub(withdrawAmount);
        totalDepositedSP = totalDepositedSP.sub(withdrawAmount);

        delegators[delegator].debtRewards = delegators[delegator].amount.mul(shareAcc);

        emit Withdraw(delegators[delegator].steemAccount, delegator, withdrawAmount);
    }

    function update(string memory steemAccount, address delegator, uint256 _amount)
        public
        onlyMinter
    {
        require(initialized == true, "Contract has not been initialized");

        uint256 prevAmount = delegators[delegator].amount;

        if (prevAmount < _amount) { // deposit
            deposit(steemAccount, delegator, _amount.sub(prevAmount));
        } else {   // withdraw
            withdraw(delegator, prevAmount.sub(_amount));
        }
    }

    
    function withdrawPeanuts() 
        public
        onlyDelegator
    {
        require(initialized == true, "Contract has not been initialized");

        // game has not started
        if (lastRewardBlock == 0) return;

        // There are new blocks created after last updating, so append new rewards before withdraw
        if(block.number > lastRewardBlock) {
            _updateRewardInfo();
        }

        uint256 pending = delegators[msg.sender].amount.mul(shareAcc).sub(delegators[msg.sender].debtRewards);
        if(pending > 0) {
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
        }

        Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);

        emit WithdrawPeanuts(delegators[msg.sender].steemAccount, msg.sender, delegators[msg.sender].availablePeanuts);

        delegators[msg.sender].availablePeanuts = 0;
    }

    // calculate reward between blocks [from, to]
    function _calculateReward(uint256 from, uint256 to) internal view returns (uint256) {
        uint256 BASE_20  = 20 * 1e6;
        uint256 BASE_10  = 10 * 1e6;
        uint256 BASE_5  = 5 * 1e6;
        uint256 BASE_2  = 25 * 1e5;
        uint256 BASE_1  = 125 * 1e4;

        require(from <= to);
        if (to <= (genesisBlock + 1000000)) {
            return to.sub(from).add(1).mul(BASE_20);
        } else if (from > (genesisBlock + 1000000) && to <= (genesisBlock + 10000000)) {
            return to.sub(from).add(1).mul(BASE_10);
        } else if (from > (genesisBlock + 10000000) && to <= (genesisBlock + 20000000)) {
            return to.sub(from).add(1).mul(BASE_5);
        } else if (from > (genesisBlock + 20000000) && to <= (genesisBlock + 30000000)) {
            return to.sub(from).add(1).mul(BASE_2);
        } else if(from > (genesisBlock + 30000000)) {
            return to.sub(from).add(1).mul(BASE_1);
        } else {    // reward maybe different under those blocks, so calculate it one by one
            if (from <= (genesisBlock + 1000000) && to >= (genesisBlock + 1000000)) {
                return BASE_20.mul((genesisBlock + 1000000).sub(from).add(1)).add(BASE_10.mul(to.sub((genesisBlock + 1000000))));
            } else if (from <= (genesisBlock + 10000000) && to >= (genesisBlock + 10000000)) {
                return BASE_10.mul((genesisBlock + 10000000).sub(from).add(1)).add(BASE_5.mul(to.sub((genesisBlock + 10000000))));
            } else if (from <= (genesisBlock + 20000000) && to >= (genesisBlock + 20000000)) {
                return BASE_5.mul((genesisBlock + 20000000).sub(from).add(1)).add(BASE_2.mul(to.sub((genesisBlock + 20000000))));
            } else {
                return BASE_2.mul((genesisBlock + 30000000).sub(from).add(1)).add(BASE_1.mul(to.sub((genesisBlock + 30000000))));
            }
        }
    }

    function _updateRewardInfo() internal
    {
        uint256 peanutsReadyToMinted = 0;
        uint256 currentBlock = block.number;

        // game has not started
        if (lastRewardBlock == 0) return;

        // make sure one block can only be calculated one time.
        // think about this situation that more than one deposit/withdraw/withdrowPeanuts transactions 
        // were exist in the same block, delegator.amout should be updated after _updateRewardInfo being 
        // invoked and it's award peanuts should be calculated next time
        if (currentBlock <= lastRewardBlock) return;

        // calculate reward peanuts under current blocks
        peanutsReadyToMinted = _calculateReward(lastRewardBlock + 1, currentBlock);

        Pnuts.mint(devAddress, peanutsReadyToMinted.div(10));
        Pnuts.mint(address(this), peanutsReadyToMinted);

        shareAcc = shareAcc.add(peanutsReadyToMinted.div(totalDepositedSP));

        lastRewardBlock = block.number;
    }

    
    // pending peanuts >= delegator.availablePeanuts
    function getPendingPeanuts() public view returns (uint256) {
        uint256 currentBlock = block.number;
        // game has not started
        if (lastRewardBlock == 0) return 0;

        // our lastRewardBlock isn't up to date, as the result, the availablePeanuts isn't
        // the right amount that delegator can award
        if (currentBlock > lastRewardBlock) {
            uint256 _shareAcc = shareAcc;
            uint256 unmintedPeanuts = _calculateReward(lastRewardBlock + 1, currentBlock);
            _shareAcc = _shareAcc.add(unmintedPeanuts.div(totalDepositedSP));
            uint256 pending = delegators[msg.sender].amount.mul(_shareAcc).sub(delegators[msg.sender].debtRewards);
            return delegators[msg.sender].availablePeanuts.add(pending);
        } else {
            return delegators[msg.sender].availablePeanuts;
        }
    }

    // Totalpending peanuts >= _totalSupply
    function getTotalPendingPeanuts() public view returns (uint256) {
        uint256 currentBlock = block.number;
        uint256 totalSupply = Pnuts.totalSupply();

        // game has not started
        if (lastRewardBlock == 0) return 0;

        // our lastRewardBlock isn't up to date, as the result, the availablePeanuts isn't
        // the right amount that delegator can award
        if (currentBlock > lastRewardBlock) {
            uint256 unmintedPeanuts = _calculateReward(lastRewardBlock + 1, currentBlock);
            return totalSupply.add(unmintedPeanuts).add(unmintedPeanuts.div(10));
        } else {
            return totalSupply;
        }
    }

    function getRewardsPerBlock() public view returns (uint256) {
        uint256 currentBlock = block.number;
        uint256 BASE_20  = 20 * 1e6;
        uint256 BASE_10  = 10 * 1e6;
        uint256 BASE_5  = 5 * 1e6;
        uint256 BASE_2  = 25 * 1e5;
        uint256 BASE_1  = 125 * 1e4;

        if (currentBlock <= (genesisBlock + 1000000)) {
            return BASE_20;
        } else if (currentBlock > (genesisBlock + 1000000) && currentBlock <= (genesisBlock + 10000000)) {
            return BASE_10;
        } else if (currentBlock > (genesisBlock + 10000000) && currentBlock <= (genesisBlock + 20000000)) {
            return BASE_5;
        } else if (currentBlock > (genesisBlock + 20000000) && currentBlock <= (genesisBlock + 30000000)) {
            return BASE_2;
        } else {
            return BASE_1;
        } 
    }

    // return VEST as unit
    function getTotalDepositedSP() public view returns (uint256) {
        return totalDepositedSP;
    }

    //Check for illegal operation by steemAccount
    function checkSteemAccount(string memory steemAccount) public view returns(bool, address){
        for (uint i = 0; i < delegatorList.length; i++) {
            if (bytes(delegators[delegatorList[i]].steemAccount).length == bytes(steemAccount).length) {
                if(keccak256(abi.encodePacked(delegators[delegatorList[i]].steemAccount)) == keccak256(abi.encodePacked(steemAccount))){
                    return(true, delegatorList[i]);
                }
            }
        }
        return (false, address(0));
    }

    function getDelegatorListLength() public view returns(uint256){
        return delegatorList.length;
    }

    function getMinter() public view returns (address) {
        return minter;
    }

    function setMinter(address _minter) 
        public
        onlyOwner
    {
        require(_minter != address(0), "Invalid minter address");
        minter = _minter;
    }

    function setDevAddress(address dev) 
        public
        onlyOwner
    {
        require(dev != address(0), "Invalid dev address");
        devAddress = dev;
    }

    function setEndowed(string memory steemAccount, address delegator, uint256 _amount, uint256 _endowedAmount) 
    public 
    onlyOwner 
    {
        require(initialized == false, "Contract already initialized");
        delegators[delegator].hasDeposited = true;
        delegators[delegator].steemAccount = steemAccount;
        delegators[delegator].amount = _amount;
        delegators[delegator].debtRewards = 0;
        delegators[delegator].availablePeanuts = _endowedAmount;
        delegatorList.push(delegator);

        totalDepositedSP = totalDepositedSP.add(_amount);
    }

    function setInitialized() 
    public 
    onlyOwner {
        require(initialized == false, "Contract already initialized");
        initialized = true;
    }
}