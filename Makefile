-include .env

deploy-sepolia: 
	forge script script/DeployOrderBook.s.sol:DeployOrderBook --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

.PHONY: all test clean deploy fund help install snapshot format anvil deploy-sepolia