default:
	@echo "What do you expect me to do?"

install:
	@echo "Installing OCMake..."
	@mkdir /usr/bin/ 2>/dev/null
	@cp make.lua /usr/bin/
