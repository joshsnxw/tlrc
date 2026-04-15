APP     = Juice.app
BINARY  = $(APP)/Contents/MacOS/Juice
SWIFTC  = swiftc
FLAGS   = -parse-as-library \
          -framework Cocoa \
          -framework IOKit \
          -framework SwiftUI \
          -framework ServiceManagement

.PHONY: build open install clean kill

build: $(APP)

$(APP): Juice.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	$(SWIFTC) $(FLAGS) Juice.swift -o $(BINARY)
	cp Info.plist $(APP)/Contents/Info.plist
	@echo "Built $(APP)"

open: build
	open $(APP)

install: build
	cp -r $(APP) /Applications/Juice.app
	@echo "Installed to /Applications"

# Kill any running instance then reopen (handy during development)
dev: build
	@pkill -x Juice 2>/dev/null || true
	open $(APP)

clean:
	rm -rf $(APP)
