# SEVEN Language — VS Code Extension

Syntax highlighting for `.seven`, `.sev`, `.sv7`, `.s7` files.

## Install (Local)

1. Copy this folder to your VS Code extensions directory:
   ```
   cp -r editor/vscode ~/.vscode/extensions/seven-language
   ```
   On Windows:
   ```
   xcopy editor\vscode %USERPROFILE%\.vscode\extensions\seven-language\ /E /I
   ```

2. Restart VS Code.

3. Open any `.seven` file — syntax highlighting is automatic.

## Features

- Keywords: `if`, `elif`, `else`, `end`, `while`, `repeat`, `each`, `func`, `match`, `case`, `try`, `catch`
- I/O: `show`, `ask`, `err`, `write`, `read`
- Builtins: `len()`, `abs()`, `min()`, `max()`, `sort()`, `range()`, etc.
- Methods: `.upper()`, `.split()`, `.startswith()`, `.repeat()`, etc.
- Word operators: `and`, `or`, `not`, `is`, `equals`, `above`, `below`
- Comments: `!!`
- Strings, numbers, operators
- Code folding on block keywords
- Auto-closing brackets and quotes
