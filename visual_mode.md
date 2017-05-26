# Tracer's Visual Mode

Visual mode can be entered while in debug mode with the `visual` command.
By default, you will have the disassembly view focused. Press `o` to focus a different view and `q` to quit.

## Disassembly View Key Shortcuts

| Key          | Action                         |
|:-------------|:-------------------------------|
| S            | Step 1 instruction             |
| Shift-S      | Step to cursor                 |
| R            | Recall 1 instruction           |
| Shift-R      | Recall to cursor               |
| P            | Move cursor to program counter |
| Shift-P      | Move program counter to cursor |

### Unimplemented key shortcuts

| Key          | Action                         |
|:-------------|:-------------------------------|
| [1-9]        | Move cursor to bookmark        |
| Shift-[1-9]  | Create bookmark                |
| Shift-F      | Step until PC reaches LR       |
| Enter        | Go to branch target            |
| C            | Center view on cursor          |

## Memory View Key Shortcuts

### Unimplemented key shortcuts

| Key          | Action                             |
|:-------------|:-----------------------------------|
| [1-9]        | Move cursor to bookmark            |
| Shift-[1-9]  | Create bookmark                    |
| G            | Prompt for location to move cursor |
| D            | Focus disassembly view at cursor   |
| Shift-D      | Focus disassembly view at *cursor  |