# fortty Makefile - wraps CMake for convenience

BUILD_DIR := build
BUILD_TYPE ?= Debug
BINARY := $(BUILD_DIR)/fortty

.PHONY: all clean distclean run install help debug release

# Default target
all: $(BINARY)

# Build the project
$(BINARY):
	@echo "=== Building fortty ($(BUILD_TYPE)) ==="
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake -DCMAKE_BUILD_TYPE=$(BUILD_TYPE) ..
	@cd $(BUILD_DIR) && $(MAKE) --no-print-directory
	@echo "=== Build complete: $(BINARY) ==="

# Debug build (default)
debug:
	@$(MAKE) BUILD_TYPE=Debug all

# Release build
release:
	@$(MAKE) BUILD_TYPE=Release all

# Clean build artifacts
clean:
	@echo "=== Cleaning build artifacts ==="
	@rm -rf $(BUILD_DIR)
	@rm -f src/*.o src/*.mod src/*.smod
	@echo "=== Clean complete ==="

# Complete clean (includes CMake cache)
distclean: clean
	@echo "=== Deep clean complete ==="

# Run the binary
run: $(BINARY)
	@echo "=== Running fortty ==="
	@./$(BINARY)

# Install (requires CMake install target)
install: $(BINARY)
	@echo "=== Installing fortty ==="
	@cd $(BUILD_DIR) && $(MAKE) install

# Help
help:
	@echo "fortty Makefile targets:"
	@echo "  make          - Build fortty (debug mode)"
	@echo "  make debug    - Build in debug mode"
	@echo "  make release  - Build in release mode"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make distclean- Complete clean"
	@echo "  make run      - Build and run fortty"
	@echo "  make install  - Install fortty"
	@echo "  make help     - Show this help"
	@echo ""
	@echo "Build type can be overridden: make BUILD_TYPE=Release"
