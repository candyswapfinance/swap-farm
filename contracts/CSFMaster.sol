// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./CSFToken.sol";
import "./CSFWorkbench.sol";

contract CSFMaster is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositTime; // time of deposit LP token
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that CSF distribution occurs.
        uint256 accCSFPerShare; // Accumulated CSFs per share, times 1e12. See below.
        uint256 lockPeriod; // lock period of  LP pool
        uint256 unlockPeriod; // unlock period of  LP pool
        bool emergencyEnable; // pool withdraw emergency enable
    }

    // treasure address
    address public governance;
    // trade claim address
    address public tradeClaimAddress;
    // The CSF TOKEN!
    CSFToken public csftoken;
    // The BENCH TOKEN!
    CSFWorkbench public bench;
    // CSF tokens created per block.
    uint256 public csfPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when csf mining starts.
    uint256 public startBlock;
    // The block number when csf mining ends.
    uint256 public endBlock;
    // mint end block num,about 10 years.
    uint256 public constant MINTEND_BLOCKNUM = 103968000;

    // Bonus muliplier for early csf makers.
    uint256 public BONUS_MULTIPLIER = 2;

    uint256 private EARLYBIRD_BLOCKNUM = 28800*10;

    uint256 private NORMAL_BLOCKNUM = 28800*360;

    // Total mint reward.
    uint256 public totalMintReward = 0;

    uint256 public farmrate = 100;

    bool private manualcsfPerBlockEnable = false;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        CSFToken _csf,
        CSFWorkbench _bench,
        uint256 _csfPerBlock,
        uint256 _startBlock
    ) public {
        csftoken = _csf;
        bench = _bench;
        csfPerBlock = _csfPerBlock;
        startBlock = _startBlock;
        governance = msg.sender;
        tradeClaimAddress = msg.sender;
        endBlock = _startBlock.add(MINTEND_BLOCKNUM);

        poolInfo.push(
            PoolInfo({
                lpToken: _csf,
                allocPoint: 1000,
                lastRewardBlock: _startBlock,
                accCSFPerShare: 0,
                lockPeriod: 0,
                unlockPeriod: 0,
                emergencyEnable: false
            })
        );

        totalAllocPoint = 1000;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "csfmaster:!governance");
        governance = _governance;
    }

    function setTradeClaimAddress(address _tradeClaimAddress) public onlyOwner{
        tradeClaimAddress = _tradeClaimAddress;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setFarmrate(uint256 _farmrate) public onlyOwner {
        farmrate = _farmrate;
        massUpdatePools();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accCSFPerShare: 0,
                lockPeriod: 0,
                unlockPeriod: 0,
                emergencyEnable: false
            })
        );
    }

    // Update the given pool's lock period and unlock period.
    function setPoolLockTime(
        uint256 _pid,
        uint256 _lockPeriod,
        uint256 _unlockPeriod
    ) public onlyOwner {
        poolInfo[_pid].lockPeriod = _lockPeriod;
        poolInfo[_pid].unlockPeriod = _unlockPeriod;
    }

    // Update the given pool's withdraw emergency Enable.
    function setPoolEmergencyEnable(uint256 _pid, bool _emergencyEnable)
        public
        onlyOwner
    {
        poolInfo[_pid].emergencyEnable = _emergencyEnable;
    }

    // Update end mint block.
    function setEndMintBlock(uint256 _endBlock) public onlyOwner {
        endBlock = _endBlock;
    }

    // Update the given pool's CSF allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );

        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        updatecsfPerBlock();
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
       
    }

    function updatecsfPerBlock() public {
        if(manualcsfPerBlockEnable){
            return;
        }
        if (block.number < startBlock+EARLYBIRD_BLOCKNUM+NORMAL_BLOCKNUM){
            csfPerBlock = 10*1e18;
        }else if(block.number < startBlock+EARLYBIRD_BLOCKNUM+NORMAL_BLOCKNUM*2){
            csfPerBlock = 8*1e18;
        }else if(block.number < startBlock+EARLYBIRD_BLOCKNUM+NORMAL_BLOCKNUM*3){
            csfPerBlock = 6*1e18;
        }else if(block.number < startBlock+EARLYBIRD_BLOCKNUM+NORMAL_BLOCKNUM*4){
            csfPerBlock = 4*1e18;
        }else{
            csfPerBlock = 2*1e18;
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 csfmint = multiplier
            .mul(csfPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        if (farmrate<100){
            csftoken.mint(tradeClaimAddress, csfmint.mul((100-farmrate)).div(100));
        }

        uint256 csfReward = csfmint.mul(farmrate).div(100);
        csfReward = csftoken.mint(address(bench), csfReward);

        totalMintReward = totalMintReward.add(csfmint);

        pool.accCSFPerShare = pool.accCSFPerShare.add(
            csfReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        uint256 toFinal = _to > endBlock ? endBlock : _to;
        if (_from >= endBlock) {
            return 0;
        }
        return toFinal.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending CSFs on frontend.
    function pendingCSF(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCSFPerShare = pool.accCSFPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {

            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 csfmint = multiplier
                .mul(csfPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);

            uint256 csfReward = csfmint.mul(farmrate).div(100);
            accCSFPerShare = accCSFPerShare.add(
                csfReward.mul(1e12).div(lpSupply)
            );
        }
        uint256 pending = user.amount.mul(accCSFPerShare).div(1e12).sub(user.rewardDebt);

        if(lpSupply != 0){
            uint256 rate = user.amount.mul(100).div(lpSupply);
            if(rate<1){
                
            }else if (rate<30) {
                pending = pending.mul(70).div(100);
            }else{
                uint256 _goverAomunt = pending.mul(rate).div(100);
                pending = pending.sub(_goverAomunt);
            }
        }
        return pending;
    }

    // Deposit LP tokens to Master for CSF allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount
    ) public whenNotPaused nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            uint256 pending = user
                .amount
                .mul(pool.accCSFPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                if (pool.lockPeriod == 0) {
                    uint256 _depositTime = now - user.depositTime;
                    if (_depositTime < 1 days) {
                        uint256 _actualReward = _depositTime
                            .mul(pending)
                            .mul(1e18)
                            .div(1 days)
                            .div(1e18);
                        uint256 _goverAomunt = pending.sub(_actualReward);
                        safeCSFTransfer(governance, _goverAomunt);
                        pending = _actualReward;
                    }
                }

                uint256 rate = 0;
                if(lpSupply != 0){
                    rate = user.amount.mul(100).div(lpSupply);
                }
                if(rate<1){
                    safeCSFTransfer(msg.sender, pending);
                }else if (rate<30) {
                    uint256 _actualReward = pending.mul(70).div(100);
                    uint256 _goverAomunt = pending.sub(_actualReward);
                    safeCSFTransfer(governance, _goverAomunt);
                    pending = _actualReward;
                    safeCSFTransfer(msg.sender, pending);
                }else{
                    uint256 _goverAomunt = pending.mul(rate).div(100);
                    pending = pending.sub(_goverAomunt);
                    safeCSFTransfer(governance, _goverAomunt);
                    safeCSFTransfer(msg.sender, pending);
                }
                
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            user.depositTime = now;
        }
        user.rewardDebt = user.amount.mul(pool.accCSFPerShare).div(1e12);
        if (_pid==0){
            bench.mint(msg.sender, _amount);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Master.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good amount");
        if (_amount > 0 && pool.lockPeriod > 0) {
            require(
                now >= user.depositTime + pool.lockPeriod,
                "withdraw: lock time not reach"
            );
            if (pool.unlockPeriod > 0) {
                require(
                    (now - user.depositTime) % pool.lockPeriod <=
                        pool.unlockPeriod,
                    "withdraw: not in unlock time period"
                );
            }
        }

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCSFPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            uint256 _depositTime = now - user.depositTime;
            if (_depositTime < 1 days) {
                if (pool.lockPeriod == 0) {
                    uint256 _actualReward = _depositTime
                        .mul(pending)
                        .mul(1e18)
                        .div(1 days)
                        .div(1e18);
                    uint256 _goverAomunt = pending.sub(_actualReward);
                    safeCSFTransfer(governance, _goverAomunt);
                    pending = _actualReward;
                }
            }

            uint256 rate = 0;
            if(lpSupply != 0){
                rate = user.amount.mul(100).div(lpSupply);
            }
            if(rate<1){
                safeCSFTransfer(msg.sender, pending);
            }else if (rate<30) {
                uint256 _actualReward = pending.mul(70).div(100);
                uint256 _goverAomunt = pending.sub(_actualReward);
                safeCSFTransfer(governance, _goverAomunt);
                pending = _actualReward;
                safeCSFTransfer(msg.sender, pending);
            }else{
                uint256 _goverAomunt = pending.mul(rate).div(100);
                pending = pending.sub(_goverAomunt);
                safeCSFTransfer(governance, _goverAomunt);
                safeCSFTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCSFPerShare).div(1e12);
        if (_pid==0){
            bench.burn(msg.sender, _amount);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            pool.lockPeriod == 0 || pool.emergencyEnable == true,
            "emergency withdraw: not good condition"
        );
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);

        if (_pid==0){
            bench.burn(msg.sender, user.amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);

        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe csf transfer function, just in case if rounding error causes pool to not have enough CSFs.
    function safeCSFTransfer(address _to, uint256 _amount) internal {
        bench.safeCSFTransfer(_to, _amount);
    }

    // set csfs for every block.
    function setCSFPerBlock(uint256 _csfPerBlock) public onlyOwner {
        require(_csfPerBlock > 0, "!csfPerBlock-0");
        manualcsfPerBlockEnable = true;
        csfPerBlock = _csfPerBlock;
        massUpdatePools();
    }

    function setManualcsfPerBlock(bool enable) public onlyOwner{
        manualcsfPerBlockEnable = enable;
    }
}
