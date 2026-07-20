// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

abstract contract BaseSpell {
    function isExecutable() external view virtual returns (bool) {
        return true;
    }

    function execute() external virtual;
}
