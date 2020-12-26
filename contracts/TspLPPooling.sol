pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ERC20Token {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface PeanutsPool {
    function genesisBlock() external view returns (uint256);
    function totalDepositedSP() external view returns (uint256);
}

contract TspLPPooling is Ownable {
    using SafeMath for uint256;
    struct Delegator {
        uint256 tspLPAmount;             // TSP-LP token
        uint256 availablePeanuts;       // minted peanuts for user
        uint256 debtRewards;            // rewards debt
        bool hasDeposited;              // set true when first time deposit
    }

    mapping(address => Delegator) public delegators;
    address[] public delegatorsList;
    uint256 public shareAcc;                        // reward peanuts per TSPLP * 1e12
    uint256 public totalDepositedTSPLP;
    uint256 public TSPLPToVests;                    // TSP-LP to vests * 1e12
    uint256 public genesisBlock;             
    uint256 public lastRewardBlock;       
    address public daemonAddress;
    address public devAddress;                      // send balance peanuts to this devAddress
    address public LPAddress;                       // address of TRX-TSP pool    

    ERC20Token Pnuts;                               // pnut token
    ERC20Token TspLP;                               // Tsp-LP token
    ERC20Token Tsp;                                 // TSP token
    PeanutsPool PnutPool;                           // pnutPool :use to cal acc

    modifier onlyDaemon(){
        require(msg.sender == daemonAddress, "Caller is not the daemon");
        _;
    }

    modifier onlyDelegator() {
        require(delegators[msg.sender].hasDeposited, "Account is not a delegator");
        _;
    }


    event DepositTSP(address delegator, uint256 amount);
    event WithdrawTSP(address delegator, uint256 amount);
    event WithdrawPeanuts(address delegator, uint256 amount);
    event UpdateData(uint256 vestsToSP);
    event InsufficientBalance();

    constructor (address _pnuts, address _pnutPool, address _tsp, address _tsplp, address _LPAddress, uint256 _tspToVests) public {
        Pnuts = ERC20Token(_pnuts);
        TspLP = ERC20Token(_tsplp);
        Tsp = ERC20Token(_tsp);
        LPAddress = _LPAddress;
        PnutPool = PeanutsPool(_pnutPool);

        shareAcc = 0;
        totalDepositedTSPLP = 0;
        genesisBlock = PnutPool.genesisBlock();
        lastRewardBlock = block.number;

//      set TSPLPToVests first time
        _updateTSPLPToVests(_tspToVests);
        shareAcc = 0;
    }

    function deposit(uint256 _amount)
        public
    {
        if (_amount == 0) return;

        uint256 tspLPBalance = TspLP.balanceOf(msg.sender);
        require(_amount <= tspLPBalance, "ERC20: transfer amount exceeds balance");

        TspLP.transferFrom(msg.sender, address(this), _amount);

        uint256 _shareAcc = _calculateCurrentAcc();

        if(!delegators[msg.sender].hasDeposited){
            delegators[msg.sender].hasDeposited = true;
            delegators[msg.sender].availablePeanuts = 0;
            delegators[msg.sender].debtRewards = _amount.mul(_shareAcc).div(1e12);
            delegators[msg.sender].tspLPAmount = _amount;
            totalDepositedTSPLP = totalDepositedTSPLP + _amount;
            delegatorsList.push(msg.sender);
            return;
        }
        if (delegators[msg.sender].tspLPAmount > 0){
            uint256 pending = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
            if (pending > 0){
                delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
            }
        }
        delegators[msg.sender].tspLPAmount = delegators[msg.sender].tspLPAmount.add(_amount);
        totalDepositedTSPLP = totalDepositedTSPLP.add(_amount);

        delegators[msg.sender].debtRewards = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12);

        emit DepositTSP(msg.sender, _amount);

    }

    function withdraw(uint256 _amount)
        public
        onlyDelegator
    {
        if (_amount == 0) return;

        if (delegators[msg.sender].tspLPAmount == 0) return;

        uint256 _shareAcc = _calculateCurrentAcc();
        uint256 pending = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        if(pending > 0){
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);
        }
        uint256 withdrawAmount;
        if (_amount >= delegators[msg.sender].tspLPAmount)
            withdrawAmount = delegators[msg.sender].tspLPAmount;
        else
            withdrawAmount = _amount;

        require(withdrawAmount <= TspLP.balanceOf(address(this)), "ERC20: transfer amount exceeds balance");
        TspLP.transfer(msg.sender, withdrawAmount);
        delegators[msg.sender].tspLPAmount = delegators[msg.sender].tspLPAmount.sub(withdrawAmount);
        totalDepositedTSPLP = totalDepositedTSPLP.sub(withdrawAmount);
        delegators[msg.sender].debtRewards = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12);

//      withdraw peanuts when cancel delegate
        if (delegators[msg.sender].tspLPAmount == 0 && delegators[msg.sender].availablePeanuts > 0){
            // do not withdraw peanuts if contract insufficentBalance
            if (delegators[msg.sender].availablePeanuts > Pnuts.balanceOf(address(this))){
                emit InsufficientBalance();
            }else{
                Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);
                emit WithdrawPeanuts(msg.sender, delegators[msg.sender].availablePeanuts);
                delegators[msg.sender].availablePeanuts = 0;
            }
        }

        emit WithdrawTSP(msg.sender, _amount);
    }

    function withdrawPeanuts()
        public
        onlyDelegator
    {
         uint256 _shareAcc = _calculateCurrentAcc();

        uint256 pending = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        if (pending > 0)
            delegators[msg.sender].availablePeanuts = delegators[msg.sender].availablePeanuts.add(pending);

        uint256 balanceOfPnut = Pnuts.balanceOf(address(this));

        if (delegators[msg.sender].availablePeanuts >= balanceOfPnut){
            emit InsufficientBalance();
            return;
        }
        
        require(delegators[msg.sender].availablePeanuts <= balanceOfPnut, "ERC20: transfer amount exceeds balance");
        Pnuts.transfer(msg.sender, delegators[msg.sender].availablePeanuts);
        delegators[msg.sender].debtRewards = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12);
        delegators[msg.sender].availablePeanuts = 0;

        emit WithdrawPeanuts(msg.sender, delegators[msg.sender].availablePeanuts);
    }

//  _tspToVests = (totalvest / totalsteem) * 1e6
    function updateData(uint256 _tspToVests)
        public
        onlyDaemon
    {
        // cul acc use the old vestsToTSPlP,then update vestsTSPLP
        shareAcc = _calculateCurrentAcc();

        _updateTSPLPToVests(_tspToVests);
        lastRewardBlock = block.number;

        emit UpdateData(_tspToVests);
    }

    function _calculateCurrentAcc() internal view returns (uint256) {
        if (lastRewardBlock >= block.number) return shareAcc;
        uint256 totalDepositedSP = PnutPool.totalDepositedSP();
        uint256 readyRewardsPerVests = _calculateReward(lastRewardBlock,block.number).mul(1e12).div(totalDepositedSP);
        return shareAcc.add(readyRewardsPerVests.mul(TSPLPToVests).div(1e18));
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

    function _updateTSPLPToVests(uint256 _vestsToTSP) internal {
        uint256 TSPinPool = Tsp.balanceOf(LPAddress);
        uint256 totalLPToken = TspLP.totalSupply();
        TSPLPToVests = TSPinPool.mul(1e12).div(totalLPToken).mul(_vestsToTSP);
    }

    function withdrawBanlanceOfPeanuts(uint256 _amount)
        public
        onlyOwner
    {
        require(Pnuts.balanceOf(address(this)) >= _amount, "Not enough balance to withdraw");
        Pnuts.transfer(devAddress, _amount);
    }

    function getPendingPeanuts() public view returns (uint256) {
        uint256 _shareAcc = _calculateCurrentAcc();
        uint256 pending = delegators[msg.sender].tspLPAmount.mul(_shareAcc).div(1e12).sub(delegators[msg.sender].debtRewards);
        return delegators[msg.sender].availablePeanuts.add(pending);
    }

       // return TSP-LP as unit
    function getTotalDepositedTSPLP() public view returns (uint256) {
        return totalDepositedTSPLP;
    }

    function getDelegatorListLength() public view returns(uint256){
        return delegatorsList.length;
    }

    function setDaemonAddress(address daemon)
        public
        onlyOwner
    {
        require(daemon != address(0), "Invalid daemon address");
        daemonAddress = daemon;    
    }

        // should do this before game start
    function setDevAddress(address dev) 
        public
        onlyOwner
    {
        require(dev != address(0), "Invalid dev address");
        devAddress = dev;
    }

    function getBalanceOfPeanuts() public view onlyOwner returns(uint256)
    {
        return Pnuts.balanceOf(address(this)); 
    }

}