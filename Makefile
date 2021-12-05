# Just a little Makefile to test things out.
macro1 = "Hello"

default:
	echo "First target is always the default."
	@echo "Suppression test"

depend: default sus
	@echo "Dependency test"

sus:
	@echo amogus
	@$(info when the imposter is sus)
