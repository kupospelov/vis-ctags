# vis-ctags

Basic ctags support for the [vis editor](https://github.com/martanne/vis).

## Usage

The plugin should first of all be
[enabled](https://github.com/martanne/vis/wiki/Plugins).

| Action           | Shortcut        | Command          | Exports            |
| ---------------- | --------------- | ---------------- | ------------------ |
| Jump to tag      | `Ctrl+]`        | `tag <word>`     | `actions.tag`      |
| List tag matches | `g+Ctrl+]`      | `tselect <word>` | `actions.tselect`  |
| Jump back        | `Ctrl+T`        | `pop`            | `actions.pop`      |
| Complete tag     | `Ctrl+N`        | `complete`       | `actions.complete` |

Then, second of all, you must create the tags file yourself, outside of this plugin,
using either universal-ctags or exuberant-ctags on the file you wish to operate on.
Finally, type `vis tags` and use the shortcut on any found tags.

There may be some generic or language-specific issues. If you find
one, or you have an idea of how to improve something, feel free to
send a patch or create a pull request.
