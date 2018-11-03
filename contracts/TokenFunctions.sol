/* Copyright (C) 2017 NexusMutual.io

  This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

  This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/ */

pragma solidity 0.4.24;

import "./NXMaster.sol";
import "./NXMToken.sol";
import "./MCR.sol";
import "./TokenController.sol";
import "./ClaimsReward.sol";
import "./TokenData.sol";
import "./QuotationData.sol";
import "./imports/openzeppelin-solidity/math/SafeMaths.sol";
import "./imports/govblocks-protocol/Governed.sol";
import "./imports/govblocks-protocol/MemberRoles.sol";
import "./Iupgradable.sol";


contract TokenFunctions is Iupgradable, Governed {
    using SafeMaths for uint;

    NXMaster public ms;
    MCR public m1;
    MemberRoles public mr;
    NXMToken public tk;
    TokenController public tc;
    TokenData public td;
    QuotationData public qd;
    ClaimsReward public cr;

    uint private constant DECIMAL1E18 = uint(10) ** 18;

    modifier onlyInternal {
        require(ms.isInternal(msg.sender) == true);
        _;
    }

    modifier onlyOwner {
        require(ms.isOwner(msg.sender) == true);
        _;
    }
    
    modifier checkPause {
        require(ms.isPause() == false);
        _;
    }

    modifier isMemberAndcheckPause {
        require(ms.isPause() == false && ms.isMember(msg.sender) == true);
        _;
    }

    constructor () public {
        dappName = "NEXUS-MUTUAL";
    }
     
    /**
    * @dev Gets current number of NXM Tokens of founders.
    */ 
    function getCurrentFounderTokens() external view returns(uint tokens) {
        tokens = tk.balanceOf(tk.founderAddress());
    }
 
    /**
    * @dev Used to set and update master address
    * @param _add address of master contract
    */
    function changeMasterAddress(address _add) public {
        if (address(ms) != address(0)) {
            require(ms.isInternal(msg.sender) == true);
        }
        ms = NXMaster(_add);
    }

    function changeMemberRolesAddress(address memberAddress) public onlyInternal {
        mr = MemberRoles(memberAddress);
    }

    /**
    * @dev Just for interface
    */
    function changeDependentContractAddress() public {
        uint currentVersion = ms.currentVersion();
        tk = NXMToken(ms.versionContractAddress(currentVersion, "TK"));
        td = TokenData(ms.versionContractAddress(currentVersion, "TD"));
        tc = TokenController(ms.versionContractAddress(currentVersion, "TC"));
        cr = ClaimsReward(ms.versionContractAddress(currentVersion, "CR"));
        qd = QuotationData(ms.versionContractAddress(currentVersion, "QD"));
        m1 = MCR(ms.versionContractAddress(currentVersion, "MCR"));
    }

    /**
    * @dev Gets the Token price in a given currency
    * @param curr Currency name.
    * @return price Token Price.
    */
    function getTokenPrice(bytes4 curr) public view returns(uint price) {
        price = m1.calculateTokenPrice(curr);
    }

    /**
    * @dev It will tell if user has locked tokens in member vote or not.
    * @param _add addressof user.
    */ 
    function voted(address _add) public view returns(bool) {
        return mr.checkRoleIdByAddress(_add, 4);
    }
    
    /**
    * @dev Adding to Member Role called Voter while Member voting.
    */ 
    function lockForMemberVote(address voter, uint time) public onlyInternal {
        if (!mr.checkRoleIdByAddress(voter, 4))
            mr.updateMemberRole(voter, 4, true, time);
        else {
            if (mr.getValidity(voter, 4) < time)
                mr.setValidityOfMember(voter, 4, time);
        }
    }

    /**
    * @dev Set the flag to check if cover note is deposited against the cover id
    * @param coverId Cover Id.
    */ 
    function depositCN(uint coverId) public onlyInternal returns (bool success) {
        uint toBurn;
        (, toBurn) = td.getDepositCNDetails(coverId);
        uint availableCNToken = _getLockedCNAgainstCover(coverId).sub(toBurn);
        require(availableCNToken > 0);
        td.setDepositCN(coverId, true, toBurn);
        success = true;    
    }

    /**
    * @dev Unlocks tokens deposited against a cover.
    * @param coverId Cover Id.
    * @param burn if set true, 50 % amount of locked cover note to burn. 
    */
    function undepositCN(uint coverId, bool burn) public onlyInternal returns (bool success) {
        uint toBurn;
        (, toBurn) = td.getDepositCNDetails(coverId);
        if (burn == true) {
            td.setDepositCN(coverId, true, toBurn.add(_getDepositCNAmount(coverId)));
        } else {
            td.setDepositCN(coverId, true, toBurn);
        }
        success = true;  
    }

    /**
    * @dev Unlocks covernote locked against a given cover 
    * @param coverId id of cover
    */ 
    function unlockCN(uint coverId) public onlyInternal {
        address _of = qd.getCoverMemberAddress(coverId);
        uint lockedCN = _getLockedCNAgainstCover(coverId);
        require(lockedCN > 0);
        require(undepositCN(coverId, false));
        uint burnAmount;
        (, burnAmount) = td.getDepositCNDetails(coverId);
        uint availableCNToken = lockedCN.sub(burnAmount);
        bytes32 reason = keccak256(abi.encodePacked("CN", _of, coverId));
        if (burnAmount == 0) {
            tc.releaseLockedTokens(_of, reason, availableCNToken);
        } else if (availableCNToken == 0) {
            tc.burnLockedTokens(_of, reason, burnAmount);
        } else {
            tc.releaseLockedTokens(_of, reason, availableCNToken);
            tc.burnLockedTokens(_of, reason, burnAmount);
        }
    }

    /**
    * @dev Change the address who can update GovBlocks member role.
    *      Called when updating to a new version.
    *      Need to remove onlyOwner to onlyInternal and update automatically at version change
    */
    function changeCanAddMemberAddress(address _newAdd) public onlyOwner {
        mr.changeCanAddMember(3, _newAdd);
        mr.changeCanAddMember(4, _newAdd);
    }

    /** 
    * @dev Called by user to pay joining membership fee
    */ 
    function payJoiningFee(address _userAddress) public payable checkPause {
        uint currentVersion = ms.currentVersion();
        if (msg.sender == address(ms.versionContractAddress(currentVersion, "Q2"))) {
            require(td.walletAddress() != address(0));
            require(td.walletAddress().send(msg.value)); //solhint-disable-line
            tc.addToWhitelist(_userAddress);
            mr.updateMemberRole(_userAddress, 3, true, 0);
        } else {
            require(!qd.refundEligible(_userAddress));
            require(!ms.isMember(_userAddress));
            require(msg.value == td.joiningFee());
            qd.setRefundEligible(_userAddress, true);
        }
    }

    function kycVerdict(address _userAddress, bool verdict) public checkPause onlyInternal {
        require(!ms.isMember(_userAddress));
        require(qd.refundEligible(_userAddress));
        require(td.walletAddress() != address(0));
        if (verdict) {
            qd.setRefundEligible(_userAddress, false);
            require(td.walletAddress().send(td.joiningFee())); //solhint-disable-line
            tc.addToWhitelist(_userAddress);
            mr.updateMemberRole(_userAddress, 3, true, 0);
        } else {
            qd.setRefundEligible(_userAddress, false);
            require(_userAddress.send(td.joiningFee())); //solhint-disable-line
        }
    }

    /**
    * @dev Called by existed member if if wish to Withdraw membership.
    */
    function withdrawMembership() public isMemberAndcheckPause {
        require(tc.totalLockedBalance(msg.sender, now) == 0); //solhint-disable-line
        require(!mr.checkRoleIdByAddress(msg.sender, 4)); // No locked tokens for Member/Governance voting
        require(cr.getAllPendingRewardOfUser(msg.sender) == 0); // No pending reward to be claimed(claim assesment).
        tk.burnFrom(msg.sender, tk.balanceOf(msg.sender));
        mr.updateMemberRole(msg.sender, 3, false, 0);
        tc.removeFromWhitelist(msg.sender); // need clarification on whitelist
    }

    function lockCN(
        uint premiumNxm,
        uint coverPeriod,
        uint coverId,
        address _of
    )
        public
        onlyInternal
        returns (uint amount)
    {
        amount = (premiumNxm.mul(5)).div(100);
        uint validity = now.add(td.lockTokenTimeAfterCoverExp()).add(coverPeriod);
        bytes32 reason = keccak256(abi.encodePacked("CN", _of, coverId));
        tc.lock(_of, reason, amount, validity);
    }

}