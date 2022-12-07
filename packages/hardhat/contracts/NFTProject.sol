pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

contract NFTProject is ERC721, Ownable {

  constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function letsMint (address _to, uint256 _id) public onlyOwner {
        _safeMint(_to, _id);
    }
}