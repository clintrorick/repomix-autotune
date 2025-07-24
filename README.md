# Repomix Autotune

Automatically generate optimal repomix configurations for repositories, targeting ≤25k tokens per output file.

## Overview

Repomix Autotune is a Python tool that analyzes your repository and automatically generates intelligent repomix configurations. It uses AI-powered suggestions to identify noise files that should be ignored, and when necessary, splits large repositories into logical subdirectories to meet token budget constraints.

### Key Features

- **Intelligent Analysis**: Scans repository structure and identifies files that add noise for LLMs
- **AI-Powered Suggestions**: Uses Claude AI to generate smart ignore patterns beyond .gitignore
- **Automatic Splitting**: When ignores alone can't achieve 25k tokens, deterministically splits repo into subdirectories
- **Multiple Output Strategies**: Creates repomix-output.xml files in logical subdirectories
- **Token Budget Management**: Precise token counting and budget optimization
- **Standard Library Only**: No external dependencies required (except optional AI features)

## Installation

### From PyPI (Recommended)

```bash
pip install repomix-autotune
```

### From Source

```bash
git clone https://github.com/anthropic/repomix-autotune.git
cd repomix-autotune
pip install -e .
```

### Development Installation

```bash
git clone https://github.com/anthropic/repomix-autotune.git
cd repomix-autotune
pip install -e ".[dev]"
```

## Quick Start

### Basic Usage

```bash
# Analyze current directory
repomix-autotune

# Analyze specific repository
repomix-autotune /path/to/repo

# Use custom token budget
repomix-autotune --target-tokens 30000

# Disable AI suggestions
repomix-autotune --no-ai

# Show what would be done without making changes
repomix-autotune --dry-run
```

### Python API

```python
from repomix_autotune import autotune_repository, quick_analyze

# Quick autotune with defaults
success = autotune_repository("/path/to/repo")

# Quick analysis without generating configs
analysis = quick_analyze("/path/to/repo")
print(f"Found {analysis.total_files} files, estimated {analysis.estimated_tokens} tokens")
```

## Command Line Interface

### Basic Commands

```bash
repomix-autotune [repository] [options]
```

### Token Budget Options

```bash
--target-tokens N          # Target token count per output file (default: 25000)
--encoding ENCODING        # Token encoding: o200k_base, cl100k_base, p50k_base
--buffer-ratio RATIO       # Buffer ratio for token budget (default: 0.1 = 10%)
```

### AI and Analysis Options

```bash
--no-ai                    # Disable AI-powered ignore pattern suggestions
--claude-model MODEL       # Claude model for AI suggestions
--max-suggestions N        # Maximum number of AI suggestions (default: 20)
```

### Repository Splitting Options

```bash
--split-strategy STRATEGY  # Strategy: auto, force, never (default: auto)
--max-splits N            # Maximum number of splits (default: 10)
--min-tokens-per-split N  # Minimum tokens per split (default: 5000)
```

### Output Options

```bash
--output-dir DIR          # Directory to save configurations
--config-name NAME        # Configuration file name (default: repomix.config.json)
--dry-run                 # Show what would be done without making changes
--format FORMAT           # Output format: json, summary, detailed
--verbose, -v             # Enable verbose logging
```

## Examples

### Example 1: Basic Repository Analysis

```bash
$ repomix-autotune
INFO: Analyzing repository: /Users/dev/my-project
INFO: Step 1: Analyzing repository structure...
INFO: Step 2: Setting up token budget...
INFO: Step 3: Assessing token budget requirements...
INFO: Step 4: Repository can use single configuration
INFO: Saved configuration to: /Users/dev/my-project/repomix.config.json

=== Results ===
Generated 1 configuration file(s)
  - repomix-output.xml
    Ignore patterns: 45
```

### Example 2: Repository Requiring Splits

```bash
$ repomix-autotune /large/repo --verbose
INFO: Analyzing repository: /large/repo
INFO: Step 1: Analyzing repository structure...

=== Repository Analysis ===
Total files: 2,543
Total size: 125.7 MB
Estimated tokens: 89,234
Binary files: 234
Generated files: 45
Build artifacts: 123
Subdirectories: 8

=== Token Budget Assessment ===
Target tokens: 25,000
Effective limit: 22,500
Estimated tokens: 89,234
Within budget: No
Overflow ratio: 3.97x
Recommended splits: 4

INFO: Step 4: Repository requires splitting
INFO: Generated 4 configuration files

=== Split Strategy: by_directory ===
Reason: Split into 4 directory groups to meet token budget
Number of splits: 4

Split: frontend
  Estimated tokens: 21,450
  Include patterns: 2

Split: backend
  Estimated tokens: 22,100
  Include patterns: 3

Split: docs-tests
  Estimated tokens: 18,900
  Include patterns: 4

Split: tools-scripts
  Estimated tokens: 19,800
  Include patterns: 2
```

### Example 3: Custom Configuration

```bash
$ repomix-autotune \
    --target-tokens 30000 \
    --encoding cl100k_base \
    --split-strategy force \
    --format detailed \
    --output-dir ./configs
```

### Example 4: AI-Powered Analysis

```bash
$ repomix-autotune --claude-model claude-3-opus-20240229
INFO: Using AI-powered ignore pattern suggestions
INFO: Generated 23 AI suggestions for ignore patterns
INFO: Configuration optimized with AI suggestions
```

## Configuration Files

### Generated Configuration Structure

```json
{
  "output": {
    "filePath": "repomix-output.xml",
    "style": "xml",
    "compress": true,
    "tokenCount": true,
    "encoding": "o200k_base"
  },
  "security": {
    "enableSecurityCheck": true
  },
  "ignore": [
    "**/*.ico",
    "**/*.png", 
    "**/node_modules/**",
    "**/__pycache__/**",
    "**/build/**",
    "**/dist/**"
  ]
}
```

### Split Repository Structure

For repositories requiring splits, multiple configuration files are created:

```
repository/
├── repomix.config.json          # Master config (excludes split dirs)
├── repomix.config.1.json        # Split 1 configuration  
├── repomix.config.2.json        # Split 2 configuration
└── repomix.config.3.json        # Split 3 configuration
```

## Python API

### Core Classes

```python
from repomix_autotune import (
    RepoAnalysis, ConfigTemplate, SplitStrategy, 
    TokenBudget, AutotuneConfig
)

# Create custom configuration
config = AutotuneConfig(
    target_tokens=30000,
    use_claude_ai=True,
    max_splits=5,
    verbose=True
)
```

### Advanced Usage

```python
from repomix_autotune import (
    analyze_repository, 
    create_budget_manager,
    create_config_generator,
    create_repository_splitter
)
from pathlib import Path

# Step-by-step analysis
repo_path = Path("/path/to/repo")

# 1. Analyze repository
analysis = analyze_repository(repo_path)
print(f"Found {analysis.total_files} files")

# 2. Create budget manager
budget_manager = create_budget_manager(target_tokens=25000)
assessment = budget_manager.assess_repository(analysis)

# 3. Generate configuration
config = AutotuneConfig(target_tokens=25000)
generator = create_config_generator(config)

if assessment["within_budget"]:
    # Single configuration
    repo_config = generator.generate_single_config(analysis, budget_manager)
    repo_config.save_to_file(repo_path / "repomix.config.json")
else:
    # Split configuration
    splitter = create_repository_splitter(budget_manager)
    split_strategy = splitter.determine_split_strategy(analysis)
    
    split_configs = generator.generate_split_configs(
        analysis, split_strategy, budget_manager
    )
    
    # Save configurations
    saved_paths = generator.save_configs(split_configs, repo_path)
    print(f"Saved {len(saved_paths)} configuration files")
```

### Customizing Ignore Patterns

```python
from repomix_autotune import ConfigTemplate, DEFAULT_LLM_NOISE_PATTERNS

# Create custom template
template = ConfigTemplate()

# Add custom ignore patterns
custom_patterns = [
    "**/custom-build/**",
    "**/*.custom-ext",
    "**/generated-*/**"
]

template.ignore_patterns = DEFAULT_LLM_NOISE_PATTERNS + custom_patterns

# Save configuration
template.save_to_file(Path("custom-repomix.config.json"))
```

## AI Integration

### Claude AI Setup

To use AI-powered ignore pattern suggestions:

1. Install Claude CLI:
   ```bash
   pip install claude-cli
   ```

2. Configure Claude CLI with your API key:
   ```bash
   claude configure
   ```

3. Run repomix-autotune with AI enabled (default):
   ```bash
   repomix-autotune  # AI enabled by default
   ```

### AI Features

- **Smart Pattern Recognition**: Identifies project-specific files to ignore
- **Context-Aware Suggestions**: Understands project type and suggests relevant patterns
- **Noise Optimization**: Focuses on removing files that add noise for LLM analysis
- **Language-Specific Intelligence**: Recognizes build tools, package managers, and frameworks

## Architecture

### Package Structure

```
repomix_autotune/
├── __init__.py          # Package exports and convenience functions
├── __main__.py          # Module entry point
├── cli.py               # Command-line interface
├── core.py              # Core dataclasses and configuration
├── analyzer.py          # Repository analysis and file discovery
├── tokenizer.py         # Token counting and budget management
├── generator.py         # Configuration generation
└── splitter.py          # Repository splitting algorithms
```

### Key Components

1. **Analyzer**: Scans repository structure, identifies file types, calculates metrics
2. **Tokenizer**: Manages token counting and budget constraints
3. **Splitter**: Implements intelligent algorithms for repository partitioning
4. **Generator**: Creates optimized repomix configurations
5. **CLI**: Provides comprehensive command-line interface

## Advanced Features

### Splitting Strategies

#### Directory-Based Splitting
Groups related directories to stay within token budgets:

```
Split 1: src/, lib/          (22,450 tokens)
Split 2: tests/, docs/       (18,900 tokens)  
Split 3: tools/, scripts/    (19,800 tokens)
```

#### File Type Splitting
Groups files by programming language or type:

```
Split 1: Python files        (21,200 tokens)
Split 2: JavaScript/TS files (20,800 tokens)
Split 3: Config/Doc files    (15,400 tokens)
```

#### Hybrid Splitting
Combines multiple criteria for optimal partitioning:

```
Split 1: Frontend (React components, styles)
Split 2: Backend (API, database, services)  
Split 3: DevOps (configs, scripts, CI/CD)
```

### Token Budget Management

```python
from repomix_autotune import TokenBudget, BudgetManager

# Create custom budget
budget = TokenBudget(
    target_tokens=30000,
    encoding="cl100k_base", 
    buffer_ratio=0.15  # 15% buffer
)

budget_manager = BudgetManager(budget)

# Assess repository
assessment = budget_manager.assess_repository(analysis)
print(f"Within budget: {assessment['within_budget']}")
print(f"Recommended splits: {assessment['recommended_splits']}")
```

### Configuration Optimization

The tool includes iterative optimization to refine configurations:

1. **Initial Analysis**: Basic repository scan and token estimation
2. **Pattern Generation**: Create ignore patterns from analysis + AI
3. **Budget Assessment**: Check if configuration meets token budget
4. **Iterative Refinement**: Add more aggressive patterns if needed
5. **Validation**: Test configuration with repomix dry-run

## Troubleshooting

### Common Issues

#### "Repository path does not exist"
```bash
# Ensure path exists and is accessible
ls -la /path/to/repo
repomix-autotune /absolute/path/to/repo
```

#### "Claude CLI not found"
```bash
# Install Claude CLI for AI features
pip install claude-cli
claude configure

# Or disable AI
repomix-autotune --no-ai
```

#### "Configuration validation failed"
```bash
# Check repomix installation
repomix --version

# Use dry-run to debug
repomix-autotune --dry-run --verbose
```

#### "Repository too large, exceeded max splits"
```bash
# Increase max splits limit
repomix-autotune --max-splits 20

# Or use more aggressive token target
repomix-autotune --target-tokens 15000
```

### Debug Mode

Enable verbose logging for detailed information:

```bash
repomix-autotune --verbose --dry-run
```

This shows:
- Repository analysis details
- Token budget calculations  
- Split strategy reasoning
- AI suggestion process
- Configuration generation steps

## Contributing

### Development Setup

```bash
git clone https://github.com/anthropic/repomix-autotune.git
cd repomix-autotune
pip install -e ".[dev]"
```

### Running Tests

```bash
pytest tests/
pytest --cov=repomix_autotune tests/
```

### Code Quality

```bash
black repomix_autotune/
isort repomix_autotune/
flake8 repomix_autotune/
mypy repomix_autotune/
```

## License

MIT License - see LICENSE file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/anthropic/repomix-autotune/issues)
- **Documentation**: This README and inline code documentation
- **Examples**: See `examples/` directory in the repository

## Changelog

### v1.0.0
- Initial release
- Core analysis and configuration generation
- AI-powered ignore pattern suggestions
- Multiple splitting strategies
- Comprehensive CLI interface
- Python API with dataclasses
- Standard library only implementation