# The packed game format

The adventure engine plays games in a binary format of its own, which [`tools/packer.cs`](tools/packer.cs) writes from
a game in the ScottFree `.dat` text format. This page gives the format, then the rules the engine plays it by. The
C# reference engine in [`tools/ReferenceEngine.cs`](tools/ReferenceEngine.cs) follows them, and the 6502 engine is
to follow them too, so a transcript of one matches the other's character for character.

## The layout

All numbers are bytes, or little-endian words where the table says so. Each table's field is its offset from the
start of the packed game, so a game can be loaded anywhere.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 2 | `SA` |
| 2 | 1 | The format's version, 1 |
| 3 | 1 | How many letters of a word are significant, 1 to 8 |
| 4 | 1 | The number of items, 10 to 255 |
| 5 | 1 | The number of rooms, room 0 included, 2 to 255 |
| 6 | 1 | The number of messages, message 0 included, up to 100 |
| 7 | 1 | The number of verbs, which is also the number of nouns, 19 to 150 |
| 8 | 1 | The room the player starts in |
| 9 | 1 | The room where treasures are stored |
| 10 | 1 | The most items the player may carry |
| 11 | 1 | The number of treasures the score counts out of |
| 12 | 1 | The item that gives light, always 9 |
| 13 | 2 | The light's turns, `$FFFF` for a light that never runs out |
| 15 | 2 | The number of actions |
| 17 | 2 | The dictionary |
| 19 | 2 | The verbs |
| 21 | 2 | The nouns |
| 23 | 2 | The rooms' exits |
| 25 | 2 | The rooms' descriptions |
| 27 | 2 | The messages |
| 29 | 2 | Where each item starts |
| 31 | 2 | The noun GET and DROP know each item by |
| 33 | 2 | The treasures |
| 35 | 2 | The items' descriptions |
| 37 | 2 | The actions |

The tables follow the header in that order.

- **The dictionary** is a count, then each entry as its length and its characters.
- **The verbs and the nouns** are each word in turn, as many bytes as the word length: in capitals, cut to the word
  length and padded with 0. A synonym, which counts as the word before it, has its first byte's top bit set. The
  format's own numbers: verb 1 is GO, 10 is GET and 18 is DROP, and nouns 1 to 6 are north, south, east, west, up
  and down. Word 0 is never matched.
- **The exits** are six bytes for each room, north to down: the room the way leads to, or 0 for none.
- **The rooms' descriptions, the messages and the items' descriptions** are strings, each ending in 0. A room
  description is shown as it is: the packer adds `I'm in a ` before each one that isn't empty and doesn't start with
  `*` in the `.dat`, and takes the `*` off the others.
- **Where each item starts** is a byte for each item: a room, 0 for none, or 255 for carried.
- **The noun GET and DROP know each item by** is a byte for each item, the noun its `.dat` description names between
  slashes at its end (`Lamp/LAMP/`), as the first of its synonyms, or 0 for an item they don't take: one with no
  word, or a word that is no noun, which the packer warns of.
- **The treasures** are a bit for each item, item *n*'s in bit *n* mod 8 of byte *n* / 8: the items whose `.dat`
  description starts with `*`.

### Text

A string's bytes below `$80` are its characters: `$0A` for a new line, and `$20` to `$7E` as in ASCII. A byte from
`$80` up is an entry of the dictionary: `$80` the first, `$81` the second, and so on. An entry holds only characters,
never other entries. The packer chooses the entries greedily: each round, the substring of 2 to 24 characters that
saves the most bytes, counting its entry's cost, until 128 are chosen or no substring saves any. A `` ` `` in the
`.dat` is a quotation mark.

### Actions

Each action is three bytes, then its conditions, then its codes:

| Byte | Field |
| --- | --- |
| 0 | The verb, or 0 for an action that happens on its own |
| 1 | The noun, 0 for any; for verb 0, the chance in 100 that it happens each turn |
| 2 | The number of conditions in the high four bits, 0 to 5, and of codes in the low four, 0 to 4 |
| 3 | The conditions, two bytes each: the type in the low five bits of the first, the value's high three bits above it, and the value's low byte in the second |
| ... | The codes, a byte each |

The packer leaves out the trailing conditions of type 0 and value 0, which the `.dat` uses for empty ones, and codes
of 0, which do nothing. An action with verb 0 and noun 0 continues the action before it.

A condition's value is an item, a room, a flag (of which the low five bits count) or a number:

| Type | Holds when |
| --- | --- |
| 0 | Always: the value is a parameter for the codes |
| 1 | The item is carried |
| 2 | The item is in the player's room |
| 3 | The item is carried or in the player's room |
| 4 | The player is in the room |
| 5 | The item is not in the player's room |
| 6 | The item is not carried |
| 7 | The player is not in the room |
| 8 | The flag is set |
| 9 | The flag is clear |
| 10 | The player carries something |
| 11 | The player carries nothing |
| 12 | The item is neither carried nor in the player's room |
| 13 | The item is in play: not in room 0 |
| 14 | The item is in room 0 |
| 15 | The counter is at most the value |
| 16 | The counter is more than the value |
| 17 | The item is where it started |
| 18 | The item is not where it started |
| 19 | The counter is the value |

The codes that need a value take the action's parameters in turn, 0 once there are none left:

| Code | Does |
| --- | --- |
| 0 | Nothing |
| 1 to 51 | Prints that message and ends its line |
| 52 | Picks the item up, or says `I can't carry any more.`; either way it takes its parameter |
| 53 | Puts the item in the player's room |
| 54 | Moves the player to the room |
| 55, 59 | Puts the item in room 0 |
| 56 | Sets flag 15, the dark |
| 57 | Clears flag 15 |
| 58 | Sets the flag |
| 60 | Clears the flag |
| 61 | Says the player is dead, clears flag 15, and moves the player to the last room |
| 62 | Puts the first item in the second room |
| 63 | Ends the game |
| 64, 76 | Shows the room |
| 65 | Gives the score; with every treasure stored, says so and ends the game |
| 66 | Lists what the player carries |
| 67 | Sets flag 0 |
| 68 | Clears flag 0 |
| 69 | Refills the light: its time is the header's again, the player carries it, and flag 16 is cleared |
| 70 | Clears the screen; a transcript shows nothing for it, and goes on at a line's start |
| 71 | Would save the game: this engine says it can't yet |
| 72 | Swaps where the two items are |
| 73 | Performs the actions after this one that continue it |
| 74 | Picks the item up, however much the player carries |
| 75 | Puts the first item where the second is |
| 77 | Counts the counter down by 1, unless it is below 0 |
| 78 | Writes the counter |
| 79 | Sets the counter to the value |
| 80 | Swaps the player's room with a saved room of its own, apart from code 87's |
| 81 | Swaps the counter with the counter the value names (its low four bits) |
| 82 | Adds the value to the counter |
| 83 | Takes the value from the counter, which goes no lower than -1 |
| 84 | Writes the command's second word in full, in capitals as the console gives it |
| 85 | Writes the command's second word as code 84 does, and ends the line |
| 86 | Ends the line |
| 87 | Swaps the player's room with the saved room the value names (its low four bits) |
| 88 | Waits about two seconds |
| 89 to 101 | Nothing |
| 102 to 149 | Prints message 52 to 99 and ends its line |

There are 32 flags, a signed 16-bit counter with 16 more to swap it with, code 80's saved room and 16 more for code
87's. All start at 0.

## The rules

### A turn

1. The actions that happen on their own run: in order, each with verb 0 whose chance comes up and whose conditions
   hold, with the actions that continue it.
2. If the player has moved, or the game is starting, the room is shown.
3. If the game is over, it says so and stops.
4. The prompt, `> `, and a command. A line with no words, or with a word the game doesn't know, gets its message, if
   any, and another prompt, and takes no turn.
5. The command is performed. If it ends the game, the room is shown if the player has moved, and the game says it
   is over.
6. The light burns.

The room is shown at the end of the turn rather than as the player moves, so what happens on its own, such as day
breaking as the player leaves a cave, has happened when it is shown.

### Commands

A command is the line's first two words, a verb and a noun; more are ignored. Each counts only to the word length.

- A word alone that is no verb but one of the directions' nouns, or N, S, E, W, U or D, is GO and that direction.
- I alone is INVENTORY.
- The first word must be a verb: one the verbs don't hold gets `I don't know that word.` and takes no turn.
- A second word that is no noun is noun 0, which only the actions with noun 0 answer. Code 84 still writes it, so
  SAY can say anything.

The command is performed:

1. GO and a direction moves the player. In the dark it says `It's dangerous to move in the dark!` first, and a way
   that leads nowhere is a fall that ends the game.
2. Otherwise the actions are tried in order. An action answers the command when it has the command's verb, and its
   noun or noun 0. The first that answers and whose conditions hold is performed, with the actions that continue
   it, and the command is done.
3. With none performed, GET and DROP take or put down the item the noun names, if it is here or carried. GET with no
   noun says `What?`, then in the dark `It's too dark to see.`, then `I don't see it here.` for an item not here
   (or a noun the game doesn't know), then `I can't carry any more.`, and otherwise takes it and says `OK`. DROP
   says `What?`, then `I'm not carrying it.`, and otherwise `OK`.
4. With none performed, an action that answered but whose conditions didn't hold gets `I can't do that yet.`; GO
   with no direction, or a word the game doesn't know, gets `Give me a direction too.`, and with a noun no action
   takes `I can't go that way.`; and anything else `I don't understand.`

### What happens on its own

An action with verb 0 happens when its chance comes up: 100 always does, and takes no random number. Any other
chance takes the next random byte *r*, and comes up when *r* × 100 / 256 is below it. The random bytes come from a
16-bit linear-feedback shift register: from the state `$ACE1`, each byte shifts it right eight times, applying
`$B400` each time a 1 shifts out, and is its low byte. Every game starts from the same state, so a transcript plays
the same each time.

### The dark and the light

It is dark while flag 15 is set and the light, item 9, is neither carried nor in the player's room. In the dark the
room is `It's too dark to see.`, and so is GET.

Each turn, the light burns while it is in play and has time left: its time counts down by one. At 0, flag 16 is set,
and a light the player has says `My light has run out!`. It goes on giving light: the game's own actions decide what
happens to it. Below 25, every fifth turn, a light the player has says `My light is growing dim.`

### Showing the room

The room's description, its exits, and the items in it:

```text
I'm in a lamp room at the top of the
lighthouse
Obvious exits: Down.
I can also see: Unlit oil lamp, Iron
chest.
```

A room with no exits has `Obvious exits: none.`, and one with no items no last line.

### Wrapping

The text is wrapped at word boundaries to one column fewer than the screen, so no line fills the screen's width and
makes the machine wrap it again. A word goes on the next line when it doesn't fit after the spaces before it, and
those spaces are dropped; at a line's start they are sent. At most a line's width of spaces wait between words, and
a word as wide as a line goes as it is.

### The engine's own text

Besides the messages above, the engine says `I'm dead!` for code 61, `I can't save the game yet.` for code 71, and
`The game is now over.` at the end. It lists what the player carries after `I'm carrying: `, or says
`I'm carrying nothing.`. The score is `I've stored `, the count, ` treasures. On a scale of 0 to 100, that rates `,
the count × 100 / the treasure count, and `.`, then `Well done!` when every treasure is stored; a game with no
treasures rates 0 and never wins this way. A list separates its exits or items with `, ` and ends in `.`.
[`tools/ReferenceEngine.cs`](tools/ReferenceEngine.cs) holds each string.
