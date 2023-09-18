-include .env

deploy-sepolia: 
	@forge script script/DeployOrderBook.s.sol:DeployOrderBook --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

push-github: 
	@git push https://$(PERSONAL_ACCESS_TOKEN)@github.com/pre-vert/Borrowed-limit-order-book.git