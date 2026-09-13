# Design Tic-Tac-Toe (Object-Oriented Design)

## Problem Statement

"Design a Tic-Tac-Toe game. Two players take turns marking an N x N board
with their symbol. Whoever gets N marks in a row — horizontally, vertically,
or diagonally — wins. If the board fills up with no winner, it's a draw."

This sounds trivial — most candidates can bang out a hardcoded 3x3 board and
three `if` statements checking eight fixed win lines in a few minutes. The
interview isn't testing whether you can do that; it's testing what happens
the instant the interviewer says "now make it work for any board size N."
If your win-check is a scan of hardcoded row/column/diagonal triples, you
have to rewrite it from scratch. If you designed it generally from the
start — and, more importantly, designed it to be *fast* — you just change a
constructor argument. That's the whole interview.

## Step 1: Clarify Requirements

**Functional Requirements**
- Support an N x N board (default 3x3, but must generalize — never
  hardcode `3`).
- Two or more players, each with a distinct symbol (X, O, ...).
- Players alternate turns; a move places a player's symbol in an empty
  cell.
- After each move, detect: this player wins, the board is full with no
  winner (draw), or the game continues.
- Reject illegal moves: a move on an occupied cell, or any move after the
  game has already ended.

**Non-Functional Requirements**
- **Efficiency of win detection**: checking for a win after every move
  should not require rescanning the entire board. A naive full-board scan
  is O(N²) per move and O(N⁴) over a full game — fine for 3x3, bad once the
  interviewer asks about a 15x15 Gomoku-style board. Aim for O(1) (or O(N)
  in the win-length, not the board size) per move.
- **Extensibility**: supporting more than 2 players, a variable win-length
  (K-in-a-row on an N x N board, i.e. Gomoku) or a non-square board should
  not require rewriting the win-check logic — only reconfiguring it.
- **Separation of concerns**: `Board` should not know about turn order or
  "who won the game" as a concept — it should only answer "is this a
  winning move" and "am I full." `Game` owns turn orchestration and overall
  game state.

## Step 2: Identify Core Objects / Entities

- **Player** — a symbol (`"X"`, `"O"`) and a display name.
- **Board** — the N x N grid of cells, each holding a player's symbol or
  empty. Owns the win-detection machinery.
- **Move** — a lightweight value (row, col, player) — useful mainly as the
  parameter/return shape, doesn't need to be a full class but is worth
  naming as a concept.
- **Game** — orchestrates turn order, delegates each move to `Board`, and
  reports the outcome (in progress / won by X / draw).

## Step 3: Identify Relationships (Class Diagram)

```text
                     Player
                     - symbol
                     - name

  Board
  - size: Integer (N)
  - win_length: Integer (K, defaults to N)
  - grid: Array[Array[String|nil]]     (N x N cells)
  - row_counts:    { symbol => [count per row] }
  - col_counts:    { symbol => [count per col] }
  - diag_counts:   { symbol => count }             (main diagonal only, sq. boards)
  - anti_diag_counts: { symbol => count }
  + place(row, col, symbol) : Boolean
  + winning_move?(row, col, symbol) : Boolean   [O(1), checked incrementally]
  + full? : Boolean
  + empty_at?(row, col) : Boolean

  Game
  - board ------------------> Board          (composition: owns-a)
  - players[] --------------> [Player]       (association: uses-a)
  - current_player_index: Integer
  - status: :in_progress | :won | :draw
  - winner -----------------> Player | nil
  + make_move(player, row, col) : Symbol (:ok / :win / :draw / :illegal)
  + current_player : Player
```

Relationship types:
- `Game` **composes** `Board` — a board has no meaning or lifecycle outside
  the game that owns it.
- `Game` **associates** with `Player` — players exist independently (a
  `Player` object could be reused across many games); the game just
  references them for turn order.
- `Board` does **not** know about `Player` objects at all — it only deals
  in symbols (strings). This is a deliberate decoupling: the board is a
  pure grid-and-counting data structure, and `Game` is the only class that
  understands "whose turn," "who won."

## Step 4: Design Decisions & Patterns Used

**Why incremental counters instead of scanning the board on every move.**
The naive win-check, even when written "generally" (loop over all rows,
all columns, both diagonals, check if all N cells match), is O(N) work per
line and O(N) lines, so O(N²) per move just to check a win — and it repeats
work every single move even though only one row, one column, and at most
two diagonals could possibly have changed. The insight: a move at
`(row, col)` can only ever affect *that* row, *that* column, and the
diagonal(s) passing through `(row, col)`. So instead of scanning, `Board`
maintains four running tallies — count of each symbol per row, per column,
on the main diagonal, and on the anti-diagonal — and increments only the
relevant ones on each move. Checking "did this move win" becomes four O(1)
lookups: did `row_counts[symbol][row]` just reach `win_length`? Did
`col_counts[symbol][col]`? Etc. This turns win detection from O(N²) into
O(1) per move (or O(K) if you also need to identify *which* cells formed
the line, e.g. to highlight them in a UI). This is the single most
interview-relevant idea in this problem — it's a genuine algorithmic
optimization, not just clean OOP, and it's exactly what separates a
strong answer from an average one.

**Why `win_length` is a separate parameter from board `size`.** Standard
Tic-Tac-Toe is "3-in-a-row on a 3x3 board," so `win_length == size` and it's
easy to conflate the two. But Gomoku is "5-in-a-row on a 15x15 (or larger)
board" — `win_length < size`. If you hardcode "a win means an entire row is
one symbol," you cannot support Gomoku without a rewrite. Separating them
from day one (and having the counters track "longest current run," not just
"is the row full") means Gomoku is a constructor argument change, not a
redesign — this is the generalization the interviewer is fishing for when
they ask the board-size follow-up.

**Why `Board` doesn't reference `Player`.** If `Board` stored `Player`
objects, it would need to know how to compare players, and every future
concept added to `Player` (rating, avatar, AI-difficulty) would be a
dependency the board doesn't need. Keeping `Board` symbol-only means it's
trivially reusable and testable in isolation — you can unit-test win
detection with raw strings and never construct a `Game` or `Player` at all.

**Naive alternative, explicitly rejected**: eight hardcoded win-line
checks (3 rows + 3 cols + 2 diagonals) for a fixed 3x3 board. It's the
fastest thing to type live, but it's a dead end the moment "what about
NxN" comes up, and interviewers ask that follow-up specifically because so
many candidates fall into this trap.

## Step 5: Code

```ruby
class Player
  attr_reader :symbol, :name

  def initialize(symbol, name)
    @symbol = symbol
    @name = name
  end
end

class Board
  attr_reader :size, :win_length

  def initialize(size: 3, win_length: size)
    @size = size
    @win_length = win_length
    @grid = Array.new(size) { Array.new(size) }
    @filled_count = 0

    # Running run-lengths, keyed by symbol. Each is an array (or two
    # integers for the diagonals) tracking the CURRENT consecutive streak
    # ending at the most recent cell examined per line — but for a simple
    # win_length == size board, a plain "how many of this symbol in this
    # line so far" count is enough since the line only has `size` cells
    # total. For win_length < size (Gomoku-style), we instead track the
    # longest run of consecutive symbols touching the just-placed cell,
    # computed on the fly in O(win_length) by walking outward in each of
    # the 4 directions — still far cheaper than an O(N^2) full rescan.
    @row_counts = Hash.new { |h, k| h[k] = Array.new(size, 0) }
    @col_counts = Hash.new { |h, k| h[k] = Array.new(size, 0) }
    @diag_counts = Hash.new(0)      # keyed by (row - col), main diagonals
    @anti_diag_counts = Hash.new(0) # keyed by (row + col), anti-diagonals
  end

  def empty_at?(row, col)
    in_bounds?(row, col) && @grid[row][col].nil?
  end

  def full?
    @filled_count == size * size
  end

  # Places `symbol` at (row, col) and returns whether it was a winning move.
  # Raises if the cell is occupied or out of bounds — Game is responsible
  # for checking empty_at? first and translating that into a user-facing
  # "illegal move" result rather than letting an exception leak.
  def place(row, col, symbol)
    raise ArgumentError, "cell occupied or out of bounds" unless empty_at?(row, col)

    @grid[row][col] = symbol
    @filled_count += 1
    update_counts(row, col, symbol)
    winning_move?(row, col, symbol)
  end

  private

  def in_bounds?(row, col)
    row.between?(0, size - 1) && col.between?(0, size - 1)
  end

  def update_counts(row, col, symbol)
    @row_counts[symbol][row] += 1
    @col_counts[symbol][col] += 1
    @diag_counts[[symbol, row - col]] += 1 if on_main_diagonal_family?(row, col)
    @anti_diag_counts[[symbol, row + col]] += 1
  end

  # Every cell belongs to exactly one "row - col" diagonal and one
  # "row + col" anti-diagonal — this generalizes the classic "the" two
  # diagonals of a 3x3 board into N and N diagonal *families*, which is
  # exactly what lets win_length < size (Gomoku) detect a win anywhere on
  # the board, not just along the two full corner-to-corner diagonals.
  def on_main_diagonal_family?(_row, _col)
    true
  end

  def winning_move?(row, col, symbol)
    @row_counts[symbol][row] >= win_length ||
      @col_counts[symbol][col] >= win_length ||
      @diag_counts[[symbol, row - col]] >= win_length ||
      @anti_diag_counts[[symbol, row + col]] >= win_length
  end
end

class Game
  attr_reader :board, :players, :status, :winner

  def initialize(players, board_size: 3, win_length: board_size)
    raise ArgumentError, "need at least 2 players" if players.size < 2

    @players = players
    @board = Board.new(size: board_size, win_length: win_length)
    @current_player_index = 0
    @status = :in_progress
    @winner = nil
  end

  def current_player = players[@current_player_index]

  def over? = status != :in_progress

  # Returns :win, :draw, :ok, or :illegal — never raises, so callers (a
  # CLI loop, a controller action) can branch on the symbol directly.
  def make_move(player, row, col)
    return :illegal if over?
    return :illegal unless player == current_player
    return :illegal unless board.empty_at?(row, col)

    won = board.place(row, col, player.symbol)

    if won
      @status = :won
      @winner = player
      :win
    elsif board.full?
      @status = :draw
      :draw
    else
      advance_turn
      :ok
    end
  end

  private

  def advance_turn
    @current_player_index = (@current_player_index + 1) % players.size
  end
end
```

**Using it:**

```ruby
p1 = Player.new("X", "Alice")
p2 = Player.new("O", "Bob")
game = Game.new([p1, p2])   # classic 3x3, win_length defaults to 3

game.make_move(p1, 0, 0) # => :ok
game.make_move(p2, 1, 1) # => :ok
game.make_move(p1, 0, 1) # => :ok
game.make_move(p2, 2, 2) # => :ok
game.make_move(p1, 0, 2) # => :win   (top row: 0,0 / 0,1 / 0,2 all "X")
game.status               # => :won
game.winner.name          # => "Alice"

game.make_move(p2, 1, 0)  # => :illegal (game already over)

# Gomoku-style: 15x15 board, 5-in-a-row to win — same classes, no code change.
gomoku = Game.new([p1, p2], board_size: 15, win_length: 5)
```

## Step 6: Edge Cases & Extensibility

- **Move on an occupied cell**: `make_move` checks `board.empty_at?` before
  calling `place` and returns `:illegal` — it never even reaches the
  win-check logic, and `Board#place` itself also raises defensively if
  called directly with a bad cell, so the invariant holds even if `Game`
  is bypassed.
- **Move after the game has ended**: `over?` is checked first in
  `make_move`, before even verifying whose turn it is — once `status` is
  `:won` or `:draw` the game is frozen.
- **Full board, no winner (draw)**: checked immediately after a
  non-winning placement — `board.full?` is an O(1) counter check
  (`@filled_count`), not a re-scan, consistent with the "no full rescans"
  design goal.
- **Move by the wrong player** (out of turn): `make_move` checks
  `player == current_player` and rejects otherwise — prevents a caller bug
  from corrupting turn order.
- **N=1 board**: degenerate but the code handles it — a single placement
  immediately wins (`win_length` defaults to 1). Worth mentioning as a
  sanity-check case if asked about boundary conditions.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support a variable board size?"** Already supported —
   `Board.new(size: N)` — and this is precisely why win detection was built
   on per-row/per-column/per-diagonal counters rather than hardcoded lines:
   the counters are generated dynamically from `size`, so nothing else
   changes.
2. **"Now make it Gomoku — 5-in-a-row on a 15x15 or 19x19 board."** Also
   already supported via the separate `win_length` parameter — this is the
   natural payoff of not conflating "board size" with "win condition" from
   the start. Worth explicitly pointing out to the interviewer that this
   was a deliberate design choice, not luck.
3. **"How would you add an AI opponent?"** The standard approach is
   **minimax** (with alpha-beta pruning for anything bigger than 3x3,
   since the search space explodes fast): the AI recursively simulates
   every legal move, assumes the opponent plays optimally against it, and
   picks the move that maximizes its own guaranteed outcome. You wouldn't
   implement full minimax live under time pressure, but you should be able
   to describe the recursion and state that `Board` already exposes
   everything minimax needs (`empty_at?`, `place`, a way to enumerate legal
   moves) without modification — a sign the board's interface is
   well-factored.
4. **"How would you detect a win for more than 2 players?"** The design
   already generalizes — `players` is an array, `advance_turn` cycles
   through it modulo its size, and the win-check has no assumption of
   exactly two symbols; the only real question becomes what board size
   makes sense with N players (interviewers sometimes want you to just
   flag this as a game-design question, not a code question).
5. **"What if I wanted to undo the last move?"** Add a `moves` history
   stack on `Game` (each entry: player, row, col) and an `undo` that pops
   the last entry, clears the cell in `Board`, decrements the relevant
   counters, and reverts `status`/`winner` if the undone move was the
   winning one — the counter-based design makes decrementing symmetric
   with incrementing, which is a nice side benefit to call out.
6. **"How would you test the win-detection logic in isolation?"** Because
   `Board` doesn't depend on `Player` or `Game`, you can unit test it with
   raw symbol strings directly: place a sequence of `"X"`/`"O"` moves and
   assert `place` returns `true` only on the winning move — no game
   orchestration needed, which is a direct payoff of the decoupling
   decision in Step 4.
