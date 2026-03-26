#!/bin/bash
#
# Build script for Solar2D ONNX Runtime WebAssembly Plugin
#
# This script compiles plugin_onnxruntime.c + ONNX Runtime C API into WASM
# for use with Solar2D HTML5 builds.
#
# Prerequisites:
#   - Emscripten SDK (emsdk) installed and activated
#   - ONNX Runtime source code built with --build_wasm_static_lib
#   - Solar2D HTML5 plugin structure
#
# Usage:
#   ./build.sh [Debug|Release]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_TYPE="${1:-Release}"

# Emscripten settings
EMCC_FLAGS=""
OUTPUT_NAME="plugin_onnxruntime"

# ONNX Runtime paths (to be configured)
ORT_ROOT="${ORT_ROOT:-$SCRIPT_DIR/onnxruntime}"
ORT_BUILD_DIR="$ORT_ROOT/build/Linux/${BUILD_TYPE}"
ORT_STATIC_LIB="$ORT_BUILD_DIR/libonnxruntime_webassembly.a"

# Include paths
ORT_INCLUDE_DIRS=(
    "$ORT_ROOT/include/onnxruntime/core/session"
    "$ORT_ROOT/include/onnxruntime/core/framework"
    "$ORT_ROOT/cmake/external/onnx/onnx"
    # Add protobuf headers if needed
)

# Solar2D HTML5 plugin paths
SOLAR2D_ROOT="${SOLAR2D_ROOT:-$SCRIPT_DIR/solar2d}"
LUA_INCLUDE="$SOLAR2D_ROOT/external/lua/include"

# Output directory
OUTPUT_DIR="$SCRIPT_DIR/build/${BUILD_TYPE,,}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Check prerequisites
# ============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Emscripten
    if ! command -v emcc &> /dev/null; then
        log_error "Emscripten (emcc) not found in PATH"
        log_error "Please install and activate Emscripten SDK:"
        log_error "  https://emscripten.org/docs/getting_started/downloads.html"
        exit 1
    fi

    log_info "Emscripten found: $(emcc --version | head -n1)"

    # Check ONNX Runtime source
    if [ ! -d "$ORT_ROOT" ]; then
        log_warn "ONNX Runtime source not found at: $ORT_ROOT"
        log_warn "Please set ORT_ROOT environment variable or clone ONNX Runtime:"
        log_warn "  git clone --recursive https://github.com/Microsoft/onnxruntime $ORT_ROOT"
        log_warn ""
        log_warn "Continuing with pre-built library check..."
    fi

    # Check ONNX Runtime static library
    if [ ! -f "$ORT_STATIC_LIB" ]; then
        log_warn "ONNX Runtime static library not found at: $ORT_STATIC_LIB"
        log_warn "You need to build ONNX Runtime with --build_wasm_static_lib flag"
        log_warn "See web/BUILD_GUIDE.md for detailed instructions"
    else
        log_info "Found ONNX Runtime static library: $ORT_STATIC_LIB"
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"
}

# ============================================================================
# Build ONNX Runtime (if needed)
# ============================================================================

build_onnx_runtime() {
    if [ -f "$ORT_STATIC_LIB" ]; then
        log_info "Using existing ONNX Runtime static library"
        return 0
    fi

    if [ ! -d "$ORT_ROOT" ]; then
        log_error "Cannot build ONNX Runtime: source directory not found"
        return 1
    fi

    log_info "Building ONNX Runtime WebAssembly static library..."
    log_info "This may take 30-60 minutes..."

    cd "$ORT_ROOT"

    # Build ONNX Runtime for WebAssembly as static library
    # Flags explanation:
    #   --build_wasm_static_lib : Build static library instead of JS/WASM bundle
    #   --enable_wasm_simd      : Enable SIMD support for better performance
    #   --skip_tests            : Skip tests (required for Release builds)
    #   --disable_rtti          : Disable RTTI to reduce binary size
    #   --disable_wasm_exception_catching : Disable exception catching for performance

    local build_flags=(
        "--build_wasm_static_lib"
        "--enable_wasm_simd"
        "--skip_tests"
        "--disable_rtti"
        "--disable_wasm_exception_catching"
    )

    if [ "$BUILD_TYPE" = "Debug" ]; then
        build_flags+=("--config=Debug")
    else
        build_flags+=("--config=Release")
    fi

    log_info "Running: ./build.sh ${build_flags[*]}"
    ./build.sh "${build_flags[@]}"

    log_info "ONNX Runtime build completed"
}

# ============================================================================
# Compile plugin
# ============================================================================

compile_plugin() {
    log_info "Compiling plugin_onnxruntime.c for WebAssembly..."

    # Prepare include flags
    local include_flags=""
    for dir in "${ORT_INCLUDE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            include_flags="$include_flags -I$dir"
        fi
    done

    # Add Lua headers if available
    if [ -d "$LUA_INCLUDE" ]; then
        include_flags="$include_flags -I$LUA_INCLUDE"
    fi

    # Emscripten compiler flags
    # -s EXPORTED_FUNCTIONS: Functions to export to JS/WASM
    # -s EXPORTED_RUNTIME_METHODS: Runtime methods to export
    # -s ALLOW_MEMORY_GROWTH: Allow WASM memory to grow dynamically
    # -s MODULARIZE: Generate a module factory function
    # -s EXPORT_NAME: Name of the exported module
    # -s USE_PTHREADS: Enable pthread support (optional, requires browser support)

    local em_flags=(
        "-O3"
        "-s" "WASM=1"
        "-s" "EXPORTED_FUNCTIONS=['_luaopen_plugin_onnxruntime']"
        "-s" "EXPORTED_RUNTIME_METHODS=['ccall', 'cwrap']"
        "-s" "ALLOW_MEMORY_GROWTH=1"
        "-s" "MODULARIZE=1"
        "-s" "EXPORT_NAME=ORTModule"
        "-s" "NO_FILESYSTEM=1"
        # For Solar2D integration:
        "-s" "SIDE_MODULE=0"  # Main module, can be linked with Solar2D
        "-s" "LINKABLE=1"
        "-s" "EXPORT_ALL=1"
    )

    # Disable exceptions and RTTI for smaller binary
    em_flags+=(
        "-fno-exceptions"
        "-fno-rtti"
    )

    # Add version definition
    em_flags+=("-DPLUGIN_VERSION=\"1.0.0-wasm\"")

    # Platform definition for HTML5
    em_flags+=("-D__EMSCRIPTEN__")

    # Compile command
    local source_file="$PROJECT_ROOT/plugin_onnxruntime.c"
    local output_file="$OUTPUT_DIR/${OUTPUT_NAME}.js"

    if [ ! -f "$source_file" ]; then
        log_error "Source file not found: $source_file"
        exit 1
    fi

    log_info "Source: $source_file"
    log_info "Output: $output_file"
    log_info "Include flags: $include_flags"

    # Check if we have ORT static library
    if [ -f "$ORT_STATIC_LIB" ]; then
        log_info "Linking with ONNX Runtime static library"
        emcc "${em_flags[@]}" \
            $include_flags \
            "$source_file" \
            "$ORT_STATIC_LIB" \
            -o "$output_file"
    else
        log_warn "ONNX Runtime static library not found, creating stub build"
        log_warn "The plugin will compile but won't have actual inference capability"
        
        # Create a minimal build without ORT linking
        # This is useful for testing the build pipeline
        emcc "${em_flags[@]}" \
            $include_flags \
            "$source_file" \
            -o "$output_file" \
            2>&1 || true
    fi

    log_info "Compilation completed"
}

# ============================================================================
# Create Solar2D plugin package
# ============================================================================

package_plugin() {
    log_info "Packaging plugin for Solar2D..."

    local package_dir="$OUTPUT_DIR/plugin_onnxruntime"
    mkdir -p "$package_dir"

    # Copy generated files
    if [ -f "$OUTPUT_DIR/${OUTPUT_NAME}.js" ]; then
        cp "$OUTPUT_DIR/${OUTPUT_NAME}.js" "$package_dir/"
    fi
    
    if [ -f "$OUTPUT_DIR/${OUTPUT_NAME}.wasm" ]; then
        cp "$OUTPUT_DIR/${OUTPUT_NAME}.wasm" "$package_dir/"
    fi

    # Create metadata.lua for Solar2D
    cat > "$package_dir/metadata.lua" << 'EOF'
local metadata = 
{
    plugin =
    {
        format = 'wasm',
        staticLibs = { "plugin_onnxruntime" },
        -- WebAssembly modules are loaded differently than native libs
        wasmFiles = { "plugin_onnxruntime.wasm" },
    },
}

return metadata
EOF

    # Create a README for the packaged plugin
    cat > "$package_dir/README.md" << EOF
# ONNX Runtime Plugin for Solar2D HTML5

This package contains the WebAssembly build of the ONNX Runtime plugin.

## Files

- plugin_onnxruntime.js - JavaScript loader/wrapper
- plugin_onnxruntime.wasm - WebAssembly binary
- metadata.lua - Solar2D plugin metadata

## Usage

Add to your build.settings:

\`\`\`lua
settings = {
    plugins = {
        ["plugin.onnxruntime"] = {
            publisherId = "com.yourcompany",
        }
    }
}
\`\`\`

## API

See the main plugin documentation for API details.
EOF

    log_info "Package created at: $package_dir"
}

# ============================================================================
# Print build summary
# ============================================================================

print_summary() {
    echo ""
    echo "=========================================="
    echo "Build Summary"
    echo "=========================================="
    echo "Build Type: $BUILD_TYPE"
    echo "Output Directory: $OUTPUT_DIR"
    echo ""

    if [ -f "$OUTPUT_DIR/${OUTPUT_NAME}.js" ]; then
        log_info "✓ JavaScript wrapper: ${OUTPUT_NAME}.js"
        ls -lh "$OUTPUT_DIR/${OUTPUT_NAME}.js"
    else
        log_error "✗ JavaScript wrapper not found"
    fi

    if [ -f "$OUTPUT_DIR/${OUTPUT_NAME}.wasm" ]; then
        log_info "✓ WebAssembly binary: ${OUTPUT_NAME}.wasm"
        ls -lh "$OUTPUT_DIR/${OUTPUT_NAME}.wasm"
    else
        log_warn "✗ WebAssembly binary not found"
    fi

    echo ""
    echo "Next Steps:"
    echo "  1. Review $OUTPUT_DIR/ for build outputs"
    echo "  2. See web/BUILD_GUIDE.md for integration instructions"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo "=========================================="
    echo "Solar2D ONNX Runtime WASM Plugin Builder"
    echo "=========================================="
    echo ""

    check_prerequisites
    
    # Optional: Build ONNX Runtime if needed
    # build_onnx_runtime
    
    compile_plugin
    package_plugin
    print_summary
}

main "$@"
