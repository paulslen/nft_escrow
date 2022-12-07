pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import "@openzeppelin/contracts/access/Ownable.sol"; 
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol



contract YourContract {
    // we should use a safe math library for integers and implement in rest of code


    //consider putting some fields in a mapping
    struct Listing {
        bool isActive;
        address seller;
        address buyer;
        address nftContractAddress;
        uint256 tokenId;
        uint256 lockTime;
        uint256 timeAtLock; // change the name of this field
        uint256 paymentPeriods; // using 30 days as a pay period for now. Will allow more customization later //consider changing parameter name
        uint256 initialPayment;
        uint256 price;
        uint256 amountPaid;
        bool hasBuyer;
    }

    // to save gas, change these to public and have getter functions 
    Listing[] public listings;
    // maybe have this be a mapping instead? mapping(uint256 => uint256) indexToSellerBalance
    uint256[] public sellerBalances;

    uint256 public constant THIRTY_DAYS_TO_SECONDS_CONVERSION = 30*24*60*60; //keep in mind we are using an epoch of 30 days, not necessarily a month //can also use a pure function to do this calculation




    /////////need to insert receiver




    // called by seller
    // seller must approve contract for nft before calling
    function createListing(
        address _nftContractAddress, 
        uint256 _tokenId, 
        uint256 _payPeriods, 
        uint256 _price, 
        uint256 _initialPayment) public {
        
        require(IERC721(_nftContractAddress).ownerOf(_tokenId) == msg.sender, "you are not the owner of this nft");
        require(IERC721(_nftContractAddress).getApproved(_tokenId) == address(this), "this address has not been approved by seller");
        //require deposit amount < listing price??
        //require months less than some amount of time?

        require(_payPeriods > 0); // include error message
        uint256 lockTime = _payPeriods * THIRTY_DAYS_TO_SECONDS_CONVERSION;
        require(lockTime % 30 == 0); // maybe unnecessary // need error message                

        Listing memory listing = Listing({
            isActive: true,
            seller: msg.sender,
            buyer: address(0),
            nftContractAddress: _nftContractAddress,
            tokenId: _tokenId,
            paymentPeriods: _payPeriods,
            price: _price,
            initialPayment: _initialPayment,
            lockTime: lockTime,  
            timeAtLock: 0,
            amountPaid: 0,
            hasBuyer: false
        });

        listings.push(listing);  
        sellerBalances.push(0); 
    }


    // called by buyer 
    function acceptPaymentPlan(uint256 _listingIndex) public payable { 

        // lmk if there are any gas optimization suggestions here on using memory vs storage. It may even be more efficient to have an instance from both storage and memory, only using the storage instance when updating variables rather than reading them 
        Listing storage listing = listings[_listingIndex];
        // should we require listing exits here to be safe? It should throw an error if the index is larger than length of listings array
        
        require(listing.isActive, "this listing is not available");
        require(!listing.hasBuyer, "There is already a buyer for this listing"); // might change this to check if the address is equal to zero address, and take this field out of struct
        require(msg.value >= listing.initialPayment, "Did not send enough for the initial payment");
        

        /** below, and in createListing function, is there a way to declare the interface then call from it? rather than wrapping an address every time?
         * ex: nftContact = IERC721(listing.address)
         * then: nftContract.ownerOf(listing.tokenId)
         * 
         * is it like this?: IERC721 nftContact = IERC721(listing.address)
         */
        require(IERC721(listing.nftContractAddress).ownerOf(listing.tokenId) == listing.seller, "seller is no longer the owner of this nft");
        require(IERC721(listing.nftContractAddress).getApproved(listing.tokenId) == address(this), "this contract is not approved by seller");

        // is there a way to check if the transfer went through in the form of a response of the transfer call?
        IERC721(listing.nftContractAddress).transferFrom(listing.seller, address(this), listing.tokenId);
        require(IERC721(listing.nftContractAddress).ownerOf(listing.tokenId) == address(this), "could not transfer nft from owner to this contract");


        listing.amountPaid = msg.value;   
        listing.buyer = msg.sender;
        listing.hasBuyer = true;
        listing.timeAtLock = block.timestamp;
        require(listing.timeAtLock > 0); // maybe unnecessary // need error message

        // consider security risks of this line
        sellerBalances[_listingIndex] = msg.value;
    }


    //called from buyer
    function makePayment(uint256 _listingIndex) public payable {
        // // how to prevent overpaying past price amount? or at least handling the extra
        // maybe have reentrant modifier here?

        require(msg.value > 0, "there was no eth sent with this payment");
        require(!hasDefaulted(_listingIndex), "buyer has defaulted");

        Listing memory listing = listings[_listingIndex];

        require(listing.isActive);

        listing.amountPaid += msg.value;
        // consider security risks of next line
        sellerBalances[_listingIndex] += msg.value;

        if (isPaidOff(_listingIndex)) {
            // emit paid off event
            // maybe change a struct veriable "paidOff" to true and require that when buyer withdraws nft
        }        
    }

    function isPaidOff(uint256 _listingIndex) public view returns (bool) {
        Listing memory listing = listings[_listingIndex];

        if (listing.amountPaid >= listing.price) {
            return true;
        }

        return false;
    }

    //change function name
    // this function needs the most attention for security. should not be able to return true if has buyer that has been making payments on time
    function hasDefaulted(uint256 _listingIndex) public view returns (bool) {
        Listing memory listing = listings[_listingIndex];

        uint256 timePassedSinceLock = block.timestamp - listing.timeAtLock;
        uint256 paymentPeriodsPassed = (timePassedSinceLock / THIRTY_DAYS_TO_SECONDS_CONVERSION);

        if (paymentPeriodsPassed >= listing.paymentPeriods) {
            paymentPeriodsPassed = listing.paymentPeriods - 1;  // can revise this and amountDueNextPayment below later for readability, but works for now
        }

        uint256 amountPerPayPeriod = getAmountPerPayPeriod(_listingIndex);
        uint256 amountDueNextPayment = amountPerPayPeriod*(paymentPeriodsPassed + 1) - listing.amountPaid;

        if (amountDueNextPayment > amountPerPayPeriod) {
            return true;
        }

        return false;
    }

    function sellerWithdrawBalance(uint256 _listingIndex) public {
        Listing storage listing = listings[_listingIndex];
        require(listing.seller == msg.sender, "you are not the seller of this nft"); // change error message
        require(sellerBalances[_listingIndex] > 0, "there is nothing to withdraw");

        // consider reentrancy here
        uint256 amountToWithdraw = sellerBalances[_listingIndex];

        require(amountToWithdraw < listing.price); // maybe unnecessary // add error message
        
        sellerBalances[_listingIndex] = 0;

        (bool callSuccess, ) = payable(msg.sender).call{value: amountToWithdraw}("");
        require(callSuccess, "transfer failed");
    }

    // this function could potentially be called from the payment function if fully paid off, or coded within the payment function after a check for it being paid off
    function buyerWithdrawNft(uint256 _listingIndex, address _to) public {
        Listing storage listing = listings[_listingIndex];

        require(listing.buyer == msg.sender, "you are not the buyer of this nft"); // change error message
        require(isPaidOff(_listingIndex), "this nft has not been paid off");

        IERC721(listing.nftContractAddress).transferFrom(address(this), _to, listing.tokenId);
    }

    function sellerWithdrawNft(uint256 _listingIndex, address _to) public {
        Listing storage listing = listings[_listingIndex];

        require(listing.seller == msg.sender, "you are not the seller of this nft");
        require(hasDefaulted(_listingIndex), "this seller has not defaulted");

        IERC721(listing.nftContractAddress).transferFrom(address(this), _to, listing.tokenId);
    }

    //change function name
    function getAmountPerPayPeriod(uint256 _listingIndex) public view returns (uint256){
        Listing memory listing = listings[_listingIndex];
        //consider calculation below - when calculating amount due, it may be less for the first month, if the initial payment was more than the required initial payment. alternativeley, this could be considered when first calculating amounts per pay period after a listing has been accepted - resuling in more on the first month, but less every month (and the same amount every month)
        return (((listing.price - listing.initialPayment) / listing.paymentPeriods) + 1); // fix rounding error by adding 1. so this will be a small additional cost to the buery. consider if any vulnerabilities here
    }

    // called by seller
    function deactivateListing(uint256 _listingIndex) public {
        Listing storage listing = listings[_listingIndex];

        require(listing.seller == msg.sender, "this is not your listing");
        require(hasDefaulted(_listingIndex) || !listing.hasBuyer, "");

        listing.isActive = false;
    }

    //need function for keeping listing active after seller defaults, but clears out the buyer. with current setup, would have to create new listing
   

    // called by seller 
    // this function is essentially so a seller can save gas by not having to create a new listing if there is a default. may be unnecessary 
    function reActivateListing(uint256 _listingIndex) public {
        Listing storage listing = listings[_listingIndex];

        require(!listing.isActive, "this listing is already inactive");
        require(listing.seller == msg.sender, "this is not your listing");
        require(IERC721(listing.nftContractAddress).ownerOf(listing.tokenId) == msg.sender, "you are not the owner of this nft");
        require(IERC721(listing.nftContractAddress).getApproved(listing.tokenId) == address(this), "this address has not been approved by seller");
        
        listing.isActive = true;
    } 


    function getTimesDue(uint256 _listingIndex) public view returns (uint256[] memory) {
        Listing storage listing = listings[_listingIndex];

        uint256 paymentPeriods = listing.paymentPeriods;
        uint256[] memory timesDue = new uint256[](paymentPeriods);

        for (uint256 i = 0; i < paymentPeriods; i++) {
            timesDue[i] = listing.timeAtLock + i*THIRTY_DAYS_TO_SECONDS_CONVERSION;
        }

        return timesDue;       
    }

    function getNextPaymemtTime(uint256 _listingIndex) public view returns (uint256) {
        Listing storage listing = listings[_listingIndex];

        uint256 timePassedSinceLock = block.timestamp - listing.timeAtLock;
        uint256 timeSinceLastDueDate = timePassedSinceLock % THIRTY_DAYS_TO_SECONDS_CONVERSION;
        uint256 timeUntilNextDueDate = THIRTY_DAYS_TO_SECONDS_CONVERSION - timeSinceLastDueDate;

        uint256 nextPaymentTime = block.timestamp + timeUntilNextDueDate;

        return nextPaymentTime;
    }

    // change function name
    function getAmountDueByPayment(uint256 _listingIndex) public view returns (uint256) {
        Listing storage listing = listings[_listingIndex];

        require(!hasDefaulted(_listingIndex), "this payment agreement has defaulted");

        uint256 timePassedSinceLock = block.timestamp - listing.timeAtLock;
        uint256 paymentPeriodsPassed = (timePassedSinceLock / THIRTY_DAYS_TO_SECONDS_CONVERSION);
        uint256 amountPerPayPeriod = getAmountPerPayPeriod(_listingIndex);

        uint256 amountDueNextPayment = amountPerPayPeriod*(paymentPeriodsPassed + 1) - listing.amountPaid;

        return amountDueNextPayment;
    }

    function isActive(uint256 _listingIndex) public view returns (bool) {
        Listing storage listing = listings[_listingIndex];

        return listing.isActive;
    }

    function timeOfFinalPayment(uint256 _listingIndex) public view returns (uint256) {
        Listing storage listing = listings[_listingIndex];

        return (listing.timeAtLock + listing.lockTime); 
    }

    function currentTime() public view returns (uint256){
        return block.timestamp;
    }
}
