// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

contract EvilContract {
  address[] public _fallbackTargets;
  uint[] public _fallbackValues;
  bytes[] public _fallbackData;

  function setFallbackParams(
    address[] calldata fallbackTargets,
    uint[] calldata fallbackValues,
    bytes[] calldata fallbackData
  ) external payable {
    require(fallbackTargets.length == fallbackValues.length, "Length mismatch");
    require(fallbackData.length == fallbackValues.length, "Length mismatch");

    uint maxLength = fallbackValues.length > _fallbackValues.length
      ? fallbackValues.length
      : _fallbackValues.length;

    uint minLength = fallbackValues.length < _fallbackValues.length
      ? fallbackValues.length
      : _fallbackValues.length;

    uint maxStorageIndex = minLength > 0 ? minLength - 1 : 0;

    for (uint i = 0; i < maxLength; i++) {
      if (i >= maxStorageIndex) {
        delete _fallbackTargets[i];
        delete _fallbackValues[i];
        delete _fallbackData[i];
      } else {
        _fallbackTargets[i] = fallbackTargets[i];
        _fallbackValues[i] = fallbackValues[i];
        _fallbackData[i] = fallbackData[i];
      }
    }
  }

  function execute(
    address[] memory targets,
    uint[] memory values,
    bytes[] memory data
  ) public {
    for (uint i = 0; i < data.length; i++) {

      (bool ok, bytes memory returndata) = targets[i].call{value: values[i]}(data[i]);

      if (ok) {
        continue;
      }

      // pass revert reason
      if (returndata.length > 0) {
        assembly {
          let returndata_size := mload(returndata)
          revert(add(32, returndata), returndata_size)
        }
      }

      revert("Low-level call failed");
    }
  }

  fallback() external payable {
    execute(_fallbackTargets, _fallbackValues, _fallbackData);
  }

}
