# vis-ctags
Basic ctags support for the [vis editor](https://github.com/martanne/vis).

## Usage
The plugin should first of all be [enabled](https://github.com/martanne/vis/wiki/Plugins). The tags file is required to be generated with the `-n` option.

| Action | Shortcut | Command |
| --- | --- | --- |
| Jump to tag | `Ctrl+]` | `tag <word>` |
| List tag matches | `g+Ctrl+]` | `tselect <word>` |
| Jump back | `Ctrl+T` | `pop` |

## Limitations
There may be some generic or language-specific issues. If you find one, or you have an idea of how to improve something, feel free to send a patch or create a pull request.
