#!/usr/bin/env bash

# repomix-autotune.sh - Automatically generate optimal repomix configurations
# Targets ≤25k tokens per output file using AI-generated ignore patterns and smart splitting

set -euo pipefail

# Global constants
readonly SCRIPT_NAME="$(basename "$0")"
TARGET_TOKEN_LIMIT=25000
readonly REPOMIX_CONFIG="repomix.config.json"
readonly TEMP_DIR="/tmp/repomix-autotune-$$"
readonly MAX_RECURSION_DEPTH=3

# Global variables
VERBOSE=false
QUIET=false
DRY_RUN=false
FORCE=false
SKIP_AI=false
TARGET_DIR="."
OUTPUT_DIR=""
ENCODING="o200k_base"

# Color codes for output
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly MAGENTA=$(tput setaf 5)
    readonly CYAN=$(tput setaf 6)
    readonly WHITE=$(tput setaf 7)
    readonly BOLD=$(tput bold)
    readonly RESET=$(tput sgr0)
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly BLUE=""
    readonly MAGENTA=""
    readonly CYAN=""
    readonly WHITE=""
    readonly BOLD=""
    readonly RESET=""
fi

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Logging functions
log_error() {
    echo "${RED}ERROR: $*${RESET}" >&2
}

log_warn() {
    echo "${YELLOW}WARNING: $*${RESET}" >&2
}

log_info() {
    if [[ "$QUIET" != true ]]; then
        echo "${CYAN}INFO: $*${RESET}"
    fi
}

log_success() {
    if [[ "$QUIET" != true ]]; then
        echo "${GREEN}SUCCESS: $*${RESET}"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "${BLUE}VERBOSE: $*${RESET}" >&2
    fi
}

# Show usage information
usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME${RESET} - Automatically generate optimal repomix configurations

${BOLD}USAGE:${RESET}
    $SCRIPT_NAME [OPTIONS] [TARGET_DIR]

${BOLD}DESCRIPTION:${RESET}
    Automatically generates optimal repomix configurations for repositories lacking
    repomix.config.json, targeting ≤25k tokens per output file. Uses AI to generate
    intelligent ignore patterns and deterministically splits repos when needed.

${BOLD}OPTIONS:${RESET}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-error output
    -n, --dry-run       Show what would be done without making changes
    -f, --force         Overwrite existing repomix.config.json files
    -s, --skip-ai       Skip AI pattern generation, use defaults only
    -o, --output DIR    Specify output directory for repomix files
    -e, --encoding ENC  Token encoding to use (default: o200k_base)
    -t, --target NUM    Target token limit (default: 25000)

${BOLD}ARGUMENTS:${RESET}
    TARGET_DIR          Directory to analyze (default: current directory)

${BOLD}EXAMPLES:${RESET}
    $SCRIPT_NAME                    # Analyze current directory
    $SCRIPT_NAME /path/to/repo      # Analyze specific directory
    $SCRIPT_NAME -v -f .            # Verbose mode, force overwrite
    $SCRIPT_NAME -t 30000 /repo     # Custom token limit

${BOLD}EXIT CODES:${RESET}
    0   Success
    1   General error
    2   Missing dependencies
    3   Invalid arguments
    64  Configuration error
EOF
}

# Check for required dependencies
check_dependencies() {
    log_verbose "Checking for required dependencies..."
    
    local missing_deps=()
    
    if ! command -v repomix >/dev/null 2>&1; then
        missing_deps+=("repomix")
    fi
    
    if ! command -v claude >/dev/null 2>&1; then
        missing_deps+=("claude")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing tools and try again."
        exit 2
    fi
    
    log_verbose "All dependencies found."
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -s|--skip-ai)
                SKIP_AI=true
                shift
                ;;
            -o|--output)
                if [[ $# -lt 2 ]]; then
                    log_error "Option $1 requires an argument."
                    exit 3
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -e|--encoding)
                if [[ $# -lt 2 ]]; then
                    log_error "Option $1 requires an argument."
                    exit 3
                fi
                ENCODING="$2"
                shift 2
                ;;
            -t|--target)
                if [[ $# -lt 2 ]]; then
                    log_error "Option $1 requires an argument."
                    exit 3
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Target token limit must be a positive integer."
                    exit 3
                fi
                TARGET_TOKEN_LIMIT="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                log_error "Use -h or --help for usage information."
                exit 3
                ;;
            *)
                if [[ -n "$TARGET_DIR" && "$TARGET_DIR" != "." ]]; then
                    log_error "Multiple target directories specified."
                    exit 3
                fi
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done
    
    # Validate target directory
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Target directory does not exist: $TARGET_DIR"
        exit 3
    fi
    
    # Convert to absolute path
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
    
    # Set output directory if not specified
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$TARGET_DIR"
    fi
    
    log_verbose "Parsed arguments:"
    log_verbose "  Target directory: $TARGET_DIR"
    log_verbose "  Output directory: $OUTPUT_DIR"
    log_verbose "  Token limit: $TARGET_TOKEN_LIMIT"
    log_verbose "  Encoding: $ENCODING"
    log_verbose "  Verbose: $VERBOSE"
    log_verbose "  Quiet: $QUIET"
    log_verbose "  Dry run: $DRY_RUN"
    log_verbose "  Force: $FORCE"
    log_verbose "  Skip AI: $SKIP_AI"
}

# Initialize temporary directory
init_temp_dir() {
    log_verbose "Creating temporary directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR"
}

# Repository analysis functions
analyze_repository() {
    log_info "Analyzing repository: $TARGET_DIR"
    
    local original_dir="$PWD"
    cd "$TARGET_DIR"
    
    # Check if it's a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_warn "Not a git repository, some features may be limited"
    fi
    
    # Get initial file count and size
    local file_count
    file_count=$(find . -type f | wc -l | tr -d ' ')
    log_verbose "Found $file_count files in repository"
    
    # Check for existing repomix config
    if [[ -f "$REPOMIX_CONFIG" ]] && [[ "$FORCE" != true ]]; then
        log_error "repomix.config.json already exists. Use -f/--force to overwrite."
        cd "$original_dir"
        exit 64
    fi
    
    cd "$original_dir"
}

# Measure current token count using repomix
measure_tokens() {
    local target_dir="${1:-$TARGET_DIR}"
    local config_file="${2:-}"
    
    log_verbose "Measuring tokens in: $target_dir"
    
    local original_dir="$PWD"
    cd "$target_dir"
    
    local repomix_args=("--encoding" "$ENCODING")
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        repomix_args+=("--config" "$config_file")
    fi
    
    # Create a temporary output file for measurement
    local temp_output="$TEMP_DIR/measure_$(basename "$target_dir")_$(date +%s).xml"
    repomix_args+=("--output" "$temp_output")
    
    # Run repomix and capture the full output to extract token count
    local repomix_output
    if repomix_output=$(repomix "${repomix_args[@]}" 2>&1); then
        # Extract token count from the summary output
        local token_count
        token_count=$(echo "$repomix_output" | grep -o 'Total Tokens: [0-9,]*' | grep -o '[0-9,]*' | tr -d ',' || echo "0")
        
        # If we didn't get a token count from the summary, try parsing the generated file
        if [[ "$token_count" == "0" && -f "$temp_output" ]]; then
            # Estimate tokens by character count (rough approximation: 4 chars per token)
            local char_count
            char_count=$(wc -c < "$temp_output" 2>/dev/null || echo "0")
            token_count=$((char_count / 4))
            log_verbose "Estimated token count from character count: $token_count"
        fi
        
        log_verbose "Current token count: $token_count"
        echo "$token_count"
    else
        log_verbose "Repomix failed, attempting fallback measurement"
        # Fallback: estimate based on file sizes
        local total_size
        total_size=$(find . -type f -exec wc -c {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
        local estimated_tokens=$((total_size / 4))
        
        log_verbose "Fallback estimated tokens: $estimated_tokens"
        echo "$estimated_tokens"
    fi
    
    # Clean up temp file
    [[ -f "$temp_output" ]] && rm -f "$temp_output"
    
    cd "$original_dir"
}

# Get repository statistics
get_repo_stats() {
    local target_dir="${1:-$TARGET_DIR}"
    
    log_verbose "Gathering repository statistics for: $target_dir"
    
    local original_dir="$PWD"
    cd "$target_dir"
    
    # Create stats object
    local stats_file="$TEMP_DIR/repo_stats.json"
    
    # Get basic file counts and types
    local total_files
    total_files=$(find . -type f | wc -l | tr -d ' ')
    
    local source_files
    source_files=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.java" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" -o -name "*.rs" -o -name "*.rb" -o -name "*.php" -o -name "*.cs" -o -name "*.swift" \) | wc -l | tr -d ' ')
    
    local config_files
    config_files=$(find . -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o -name "*.ini" -o -name "*.conf" -o -name "*.config" \) | wc -l | tr -d ' ')
    
    local docs_files
    docs_files=$(find . -type f \( -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.adoc" \) | wc -l | tr -d ' ')
    
    # Get directory structure depth
    local max_depth
    max_depth=$(find . -type d | awk -F/ 'NF > max {max = NF} END {print max-1}')
    
    # Generate JSON stats
    jq -n \
        --arg total_files "$total_files" \
        --arg source_files "$source_files" \
        --arg config_files "$config_files" \
        --arg docs_files "$docs_files" \
        --arg max_depth "$max_depth" \
        --arg target_dir "$target_dir" \
        '{
            target_dir: $target_dir,
            total_files: ($total_files | tonumber),
            source_files: ($source_files | tonumber),
            config_files: ($config_files | tonumber),
            docs_files: ($docs_files | tonumber),
            max_depth: ($max_depth | tonumber)
        }' > "$stats_file"
    
    log_verbose "Repository stats: total=$total_files, source=$source_files, config=$config_files, docs=$docs_files, depth=$max_depth"
    
    cd "$original_dir"
    echo "$stats_file"
}

# Generate AI-powered ignore patterns
generate_ai_patterns() {
    local target_dir="${1:-$TARGET_DIR}"
    local stats_file="${2:-}"
    
    # Skip AI if requested
    if [[ "$SKIP_AI" == true ]]; then
        log_info "Skipping AI pattern generation, using defaults"
        generate_default_patterns "$target_dir"
        return
    fi
    
    log_info "Generating AI ignore patterns for: $target_dir"
    
    local original_dir="$PWD"
    cd "$target_dir"
    
    # Collect repository information for AI analysis
    local repo_info_file="$TEMP_DIR/repo_info.txt"
    
    # Get directory structure (limited depth to avoid overwhelming AI)
    echo "=== REPOSITORY STRUCTURE ===" > "$repo_info_file"
    find . -type d -depth +2 | head -50 | sort >> "$repo_info_file" || true
    
    echo -e "\n=== FILE TYPES AND COUNTS ===" >> "$repo_info_file"
    find . -type f -name "*.*" | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20 >> "$repo_info_file" || true
    
    echo -e "\n=== LARGE FILES (>1MB) ===" >> "$repo_info_file"
    find . -type f -size +1M -exec ls -lh {} \; | head -10 >> "$repo_info_file" 2>/dev/null || true
    
    echo -e "\n=== EXISTING .gitignore ===" >> "$repo_info_file"
    if [[ -f ".gitignore" ]]; then
        cat ".gitignore" >> "$repo_info_file"
    else
        echo "No .gitignore found" >> "$repo_info_file"
    fi
    
    echo -e "\n=== PACKAGE/BUILD FILES ===" >> "$repo_info_file"
    find . -maxdepth 2 -type f \( -name "package.json" -o -name "Cargo.toml" -o -name "pom.xml" -o -name "build.gradle" -o -name "Makefile" -o -name "CMakeLists.txt" -o -name "setup.py" -o -name "requirements*.txt" -o -name "go.mod" \) >> "$repo_info_file" 2>/dev/null || true
    
    # Create AI prompt
    local ai_prompt="$TEMP_DIR/ai_prompt.txt"
    cat > "$ai_prompt" << 'EOF'
You are an expert at analyzing code repositories and generating optimal ignore patterns for AI/LLM processing tools like repomix.

Your task is to analyze the repository information below and generate ignore patterns that will:
1. Remove files that add noise for LLMs (favicons, binaries, SQLite DBs, build artifacts, generated files)
2. Keep essential source code, documentation, and configuration files
3. Target a final output of ~25,000 tokens or less

Based on the repository information provided, generate a JSON array of ignore patterns using fast-glob syntax. Focus on:

- Binary files (images, videos, audio, executables, archives)
- Build artifacts and generated files (dist/, build/, target/, node_modules/, __pycache__/, .git/)
- IDE and editor files (.vscode/, .idea/, *.swp, *.tmp)
- Log files and temporary files (*.log, *.tmp, *.cache)
- Database files (*.db, *.sqlite, *.sqlite3)
- Large data files and assets that don't contribute to code understanding
- Minified files (*.min.js, *.min.css)
- Documentation assets (if excessive) like screenshots in docs/

Return ONLY a valid JSON array of patterns, no other text. Example format:
["node_modules/**", "*.log", "dist/**", "*.min.js", "*.sqlite"]

Repository Information:
EOF
    
    # Append repo info to prompt
    cat "$repo_info_file" >> "$ai_prompt"
    
    # Call Claude AI to generate patterns
    log_verbose "Calling Claude AI to generate ignore patterns..."
    local patterns_file="$TEMP_DIR/ai_patterns.json"
    
    # Try different Claude CLI invocation methods with timeout
    local claude_success=false
    
    # Method 1: Try with -p flag (prompt file) with timeout
    if timeout 30 claude -p "$ai_prompt" > "$patterns_file" 2>/dev/null; then
        claude_success=true
    # Method 2: Try piping the prompt with timeout
    elif timeout 30 bash -c "cat '$ai_prompt' | claude" > "$patterns_file" 2>/dev/null; then
        claude_success=true
    # Method 3: Try with standard input with timeout
    elif timeout 30 claude < "$ai_prompt" > "$patterns_file" 2>/dev/null; then
        claude_success=true
    fi
    
    if [[ "$claude_success" == true ]]; then
        # Clean up the output - remove any non-JSON content
        local cleaned_json="$TEMP_DIR/cleaned_patterns.json"
        
        # Extract JSON array from the output (look for lines starting with [ and ending with ])
        if grep -o '\[.*\]' "$patterns_file" > "$cleaned_json" 2>/dev/null; then
            # Validate JSON output
            if jq empty "$cleaned_json" 2>/dev/null; then
                log_verbose "AI generated $(jq length "$cleaned_json") ignore patterns"
                log_verbose "Generated patterns: $(jq -c . "$cleaned_json")"
                echo "$cleaned_json"
            else
                log_warn "AI generated invalid JSON, falling back to default patterns"
                generate_default_patterns "$target_dir"
            fi
        else
            log_warn "Could not extract JSON from AI output, falling back to default patterns"
            generate_default_patterns "$target_dir"
        fi
    else
        log_warn "Failed to call Claude AI, falling back to default patterns"
        generate_default_patterns "$target_dir"
    fi
    
    cd "$original_dir"
}

# Generate default ignore patterns as fallback
generate_default_patterns() {
    local target_dir="${1:-$TARGET_DIR}"
    
    log_verbose "Generating default ignore patterns"
    
    local patterns_file="$TEMP_DIR/default_patterns.json"
    
    # Create comprehensive default patterns
    jq -n '[
        "node_modules/**",
        ".*/**",
        "build/**",
        "dist/**",
        "target/**",
        "__pycache__/**",
        "*.pyc",
        ".git/**",
        ".svn/**",
        ".hg/**",
        "vendor/**",
        "deps/**",
        "*.log",
        "*.tmp",
        "*.temp",
        "*.cache",
        "*.swp",
        "*.swo",
        "*~",
        ".DS_Store",
        "Thumbs.db",
        "*.sqlite",
        "*.sqlite3",
        "*.db",
        "*.exe",
        "*.dll",
        "*.so",
        "*.dylib",
        "*.bin",
        "*.zip",
        "*.tar.gz",
        "*.rar",
        "*.7z",
        "*.ico",
        "*.png",
        "*.jpg",
        "*.jpeg",
        "*.gif",
        "*.svg",
        "*.bmp",
        "*.tiff",
        "*.webp",
        "*.mp4",
        "*.avi",
        "*.mov",
        "*.wmv",
        "*.mp3",
        "*.wav",
        "*.ogg",
        "*.pdf",
        "*.doc",
        "*.docx",
        "*.xls",
        "*.xlsx",
        "*.ppt",
        "*.pptx",
        "*.min.js",
        "*.min.css",
        "coverage/**",
        "test-results/**",
        "*.coverage",
        ".nyc_output/**",
        "*.lock",
        "yarn.lock",
        "package-lock.json",
        "Pipfile.lock",
        "poetry.lock",
        "Cargo.lock"
    ]' > "$patterns_file"
    
    echo "$patterns_file"
}

# Deterministic directory splitting when tokens exceed limit
split_repository() {
    local target_dir="${1:-$TARGET_DIR}"
    local current_tokens="$2"
    local recursion_depth="${3:-0}"
    
    log_info "Splitting repository: $target_dir (tokens: $current_tokens, depth: $recursion_depth)"
    
    if [[ $recursion_depth -ge $MAX_RECURSION_DEPTH ]]; then
        log_warn "Maximum recursion depth reached, stopping split"
        return 1
    fi
    
    local original_dir="$PWD"
    cd "$target_dir"
    
    # Find directories with the most files (deterministic splitting)
    local split_dirs=()
    local split_file="$TEMP_DIR/split_dirs_$recursion_depth.txt"
    
    # Get directories sorted by file count (largest first)
    find . -mindepth 1 -maxdepth 1 -type d ! -name ".*" -print0 | \
        while IFS= read -r -d '' dir; do
            local file_count
            file_count=$(find "$dir" -type f | wc -l | tr -d ' ')
            echo "$file_count:$dir"
        done | sort -rn > "$split_file"
    
    # Select directories that together contain ~50% of files
    local total_files
    total_files=$(find . -type f | wc -l | tr -d ' ')
    local target_files=$((total_files / 2))
    local accumulated_files=0
    
    while IFS=':' read -r file_count dir_path && [[ $accumulated_files -lt $target_files ]]; do
        split_dirs+=("$dir_path")
        accumulated_files=$((accumulated_files + file_count))
        log_verbose "Selected $dir_path for splitting ($file_count files)"
    done < "$split_file"
    
    # If no suitable directories found, try alternative splitting
    if [[ ${#split_dirs[@]} -eq 0 ]]; then
        log_verbose "No suitable directories for splitting, trying alternative approach"
        # Split by alphabetical order as fallback
        find . -mindepth 1 -maxdepth 1 -type d ! -name ".*" | sort | head -3 > "$split_file.alt"
        while IFS= read -r dir_path; do
            split_dirs+=("$dir_path")
        done < "$split_file.alt"
    fi
    
    if [[ ${#split_dirs[@]} -eq 0 ]]; then
        log_warn "No directories available for splitting"
        cd "$original_dir"
        return 1
    fi
    
    # Create split results
    local split_results=()
    for split_dir in "${split_dirs[@]}"; do
        local abs_split_dir="$(cd "$split_dir" && pwd)"
        log_verbose "Processing split directory: $abs_split_dir"
        
        # Generate patterns for this subdirectory
        local patterns_file
        patterns_file=$(generate_ai_patterns "$abs_split_dir")
        
        # Generate config for this subdirectory
        generate_config_for_dir "$abs_split_dir" "$patterns_file" "$((recursion_depth + 1))"
        
        # Measure tokens in this subdirectory
        local split_tokens
        split_tokens=$(measure_tokens "$abs_split_dir" "$abs_split_dir/$REPOMIX_CONFIG")
        
        # If still too large, recursively split
        if [[ $split_tokens -gt $TARGET_TOKEN_LIMIT ]] && [[ $recursion_depth -lt $((MAX_RECURSION_DEPTH - 1)) ]]; then
            log_verbose "Subdirectory $split_dir still exceeds limit ($split_tokens tokens), recursing"
            split_repository "$abs_split_dir" "$split_tokens" "$((recursion_depth + 1))"
        fi
        
        split_results+=("$split_dir:$split_tokens")
    done
    
    # Update parent config to exclude split directories
    local parent_ignore_patterns=()
    for split_dir in "${split_dirs[@]}"; do
        parent_ignore_patterns+=("${split_dir#./}/**")
    done
    
    cd "$original_dir"
    
    # Store split results for parent config generation
    echo "${split_results[*]}" > "$TEMP_DIR/split_results_${recursion_depth}.txt"
    echo "${parent_ignore_patterns[*]}" > "$TEMP_DIR/parent_ignores_${recursion_depth}.txt"
}

# Generate repomix configuration
generate_config() {
    local target_dir="${1:-$TARGET_DIR}"
    local patterns_file="${2:-}"
    local recursion_depth="${3:-0}"
    
    log_info "Generating repomix configuration for: $target_dir"
    
    generate_config_for_dir "$target_dir" "$patterns_file" "$recursion_depth"
}

# Generate config for a specific directory
generate_config_for_dir() {
    local target_dir="$1"
    local patterns_file="$2"
    local recursion_depth="${3:-0}"
    
    local original_dir="$PWD"
    cd "$target_dir"
    
    local config_file="$target_dir/$REPOMIX_CONFIG"
    
    # Load ignore patterns
    local ignore_patterns="[]"
    if [[ -n "$patterns_file" && -f "$patterns_file" ]]; then
        ignore_patterns=$(cat "$patterns_file")
    fi
    
    # Add parent ignore patterns if this is a root directory with splits
    local parent_ignores_file="$TEMP_DIR/parent_ignores_${recursion_depth}.txt"
    if [[ -f "$parent_ignores_file" ]]; then
        local parent_patterns
        parent_patterns=$(cat "$parent_ignores_file")
        if [[ -n "$parent_patterns" ]]; then
            # Convert space-separated list to JSON array
            local parent_json
            parent_json=$(echo "$parent_patterns" | tr ' ' '\n' | jq -R . | jq -s .)
            # Merge with existing patterns
            ignore_patterns=$(echo "$ignore_patterns" "$parent_json" | jq -s 'add | unique')
        fi
    fi
    
    # Generate output filename based on directory
    local output_filename="repomix-output.xml"
    if [[ "$target_dir" != "$TARGET_DIR" ]]; then
        local dir_name
        dir_name=$(basename "$target_dir")
        output_filename="repomix-output-${dir_name}.xml"
    fi
    
    local output_path="$target_dir/$output_filename"
    
    # Create repomix config JSON
    local config_json
    config_json=$(jq -n \
        --argjson ignore "$ignore_patterns" \
        --arg encoding "$ENCODING" \
        --arg output_path "$output_path" \
        --arg target_tokens "$TARGET_TOKEN_LIMIT" \
        '{
            include: [],
            ignore: $ignore,
            output: {
                filePath: $output_path,
                style: "xml",
                headerText: "Repository packed by repomix-autotune",
                topFilesLength: 5,
                showLineNumbers: false,
                removeComments: false,
                removeEmptyLines: false,
                instructionFilePath: "",
                includeEmptyDirectories: false
            },
            security: {
                enableSecurityCheck: true
            },
            tokenCount: {
                encoding: $encoding,
                enableTokenCount: true
            }
        }')
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would create $config_file with:"
        echo "$config_json" | jq .
    else
        echo "$config_json" > "$config_file"
        log_success "Created repomix config: $config_file"
        
        # Test the configuration
        if repomix --config "$config_file" >/dev/null 2>&1; then
            local final_tokens
            final_tokens=$(measure_tokens "$target_dir" "$config_file")
            log_success "Configuration validated. Final token count: $final_tokens"
            
            if [[ $final_tokens -gt $TARGET_TOKEN_LIMIT ]]; then
                log_warn "Token count ($final_tokens) still exceeds target ($TARGET_TOKEN_LIMIT)"
            fi
        else
            log_warn "Configuration test failed, but config file was created"
        fi
    fi
    
    cd "$original_dir"
}

# Main workflow orchestration
main() {
    log_info "Starting $SCRIPT_NAME..."
    
    # Initialize and validate environment
    check_dependencies
    parse_args "$@"
    init_temp_dir
    
    # Analyze the repository
    analyze_repository
    
    # Get repository statistics
    local stats_file
    stats_file=$(get_repo_stats "$TARGET_DIR")
    
    # Generate AI-powered ignore patterns
    local patterns_file
    patterns_file=$(generate_ai_patterns "$TARGET_DIR" "$stats_file")
    
    # Create initial configuration
    generate_config "$TARGET_DIR" "$patterns_file" 0
    
    # Measure tokens with the generated configuration
    local initial_tokens
    initial_tokens=$(measure_tokens "$TARGET_DIR" "$TARGET_DIR/$REPOMIX_CONFIG")
    
    log_info "Initial token count: $initial_tokens (target: $TARGET_TOKEN_LIMIT)"
    
    # If tokens exceed limit, split repository
    if [[ $initial_tokens -gt $TARGET_TOKEN_LIMIT ]]; then
        log_info "Token count exceeds limit, initiating repository splitting..."
        if split_repository "$TARGET_DIR" "$initial_tokens" 0; then
            # Regenerate root config with split directory exclusions
            generate_config "$TARGET_DIR" "$patterns_file" 0
            
            # Final measurement
            local final_tokens
            final_tokens=$(measure_tokens "$TARGET_DIR" "$TARGET_DIR/$REPOMIX_CONFIG")
            log_info "Final root token count: $final_tokens"
        else
            log_warn "Repository splitting failed, using single configuration"
        fi
    else
        log_success "Token count within limits, no splitting required"
    fi
    
    # Summary
    log_success "Configuration generation completed!"
    
    if [[ "$DRY_RUN" != true ]]; then
        log_info "Generated files:"
        find "$TARGET_DIR" -name "$REPOMIX_CONFIG" -o -name "repomix-output*.xml" | sort
    fi
    
    log_info "To run repomix with the generated configuration:"
    log_info "  cd $TARGET_DIR && repomix"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi