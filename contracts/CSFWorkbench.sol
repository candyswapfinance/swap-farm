// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./CSFToken.sol";

// CSFWorkbench with Governance.
contract CSFWorkbench is ERC20('CSFWorkbench Token', 'CSFG'), Ownable {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (Craftsman).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from ,uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }

    // The CSF TOKEN!
    CSFToken public csf;

    constructor(
        CSFToken _csf
    ) public {
        csf = _csf;
    }

    // Safe CSF transfer function, just in case if rounding error causes pool to not have enough VVSs.
    function safeCSFTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 csfBal = csf.balanceOf(address(this));
        if (_amount > csfBal) {
            csf.transfer(_to, csfBal);
        } else {
            csf.transfer(_to, _amount);
        }
    }
}
