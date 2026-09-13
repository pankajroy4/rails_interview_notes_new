# Design Chess (Object-Oriented Design)

## Problem Statement

"Design a chess game. Model the board, the pieces and their movement
rules, and the core game loop — including detecting check and checkmate.
You don't need to implement every special rule (castling, en passant,
promotion) in full, but tell me how you'd model the pieces so that adding
a new rule doesn't mean touching every other piece's code."

Chess is the classic "polymorphism stress test" of LLD interviews. There
are six piece types, each with genuinely different movement rules, plus a
handful of global rules (check, checkmate, moving into check is illegal)
that apply uniformly across all of them. The candidates who struggle are
the ones who write a single `Piece` class with a `type` field and a giant
`case piece_type` inside `Board#valid_moves`. The candidates who do well
give each piece its own `valid_moves` method and let the board and game
stay ignorant of what a bishop even is.

## Step 1: Clarify Requirements

**Functional Requirements**
- An 8x8 board of squares; each square optionally holds one piece.
- Six piece types (Pawn, Rook, Knight, Bishop, Queen, King), each with its
  own legal-move pattern.
- Two players (White, Black) alternate turns; a move is only legal for the
  player whose turn it is, moving their own piece.
- A move that captures an opposing piece removes it from the board.
- Detect **check** (a player's king is under attack), **checkmate**
  (in check with no legal move that escapes it), and — time permitting —
  **stalemate** (not in check, but no legal move at all).
- A move that would leave the moving player's own king in check is illegal
  (you cannot "move into check," even to block or capture).

**Non-Functional Requirements**
- **Extensibility**: adding or modifying a piece's movement rule should
  only touch that piece's class — never `Board` or `Game`.
- **Auditability**: the game should be able to produce a move history
  (for undo, replay, or "show me the game so far") without bolting it on
  after the fact.
- **Honesty about scope**: castling, en passant, and pawn promotion are
  real special-case rules layered on top of the base movement system, not
  something to silently skip — say explicitly how you'd add them rather
  than pretending the base design already covers them.

## Step 2: Identify Core Objects / Entities

- **Position** — a value object for a square's coordinates (row, col, or
  algebraic notation like `"e4"`); immutable, comparable, hashable.
- **Piece** (abstract) → `Pawn`, `Rook`, `Knight`, `Bishop`, `Queen`,
  `King` — each owns its own `valid_moves(board, position)`.
- **Square** — one cell of the board; holds at most one `Piece`.
- **Board** — the 8x8 grid of `Square`s; answers "what's at this position,"
  "is this position under attack by color X."
- **Move** — captures from/to/piece/captured-piece for one turn — this is
  the object that makes move history, undo, and check-detection-by-
  simulation all tractable, the same way `ParkingTicket` made multi-spot
  release tractable in the parking lot problem.
- **Player** — color (White/Black) plus identity.
- **Game** — orchestrates turns, calls into `Board` to validate and apply
  moves, tracks move history, and owns check/checkmate detection.

## Step 3: Identify Relationships (Class Diagram)

```text
Position (value object)
- row, col
+ ==, hash

                    Piece (abstract)
                    - color
                    - position
                    + valid_moves(board) : [Position]   [abstract]
                    + symbol : String                    [abstract]
                         ^
      _______________|___________________________________
     |        |         |          |          |           |
   Pawn      Rook     Knight     Bishop      Queen        King
 (fwd 1-2,  (straight (L-shape) (diagonal) (rook+bishop) (1 step any
  diag       any dist,                      combined)      dir; castling
  capture)   blocked)                                       as special case)

  Square                          Board
  - position ---> Position        - squares: 8x8 grid of Square (composition)
  - piece  ------> Piece | nil     + piece_at(position)
                                    + move_piece(from, to)
                                    + squares_attacked_by(color) : Set[Position]
                                    + king_position(color)
                                    + in_check?(color)

  Move
  - from, to -----> Position
  - piece --------> Piece
  - captured_piece -> Piece | nil

  Player
  - color, name

  Game
  - board -------------> Board            (composition: owns-a)
  - players[] ----------> [Player]        (association: uses-a)
  - move_history[] -----> [Move]
  - current_turn: :white | :black
  + move(from, to) : Symbol (:ok / :check / :checkmate / :illegal)
  + checkmate?(color) : Boolean
```

Relationship types:
- `Pawn`/`Rook`/`Knight`/`Bishop`/`Queen`/`King` **inherit** from `Piece`
  (is-a) — this is the crux of the whole design.
- `Board` **composes** `Square`s, and each `Square` **associates** with at
  most one `Piece` (a piece can move between squares; its lifecycle isn't
  owned by any one square).
- `Game` **composes** `Board` and its `move_history` (a `Move` list); it
  **associates** with `Player`s.
- `Move` associates `Position`s and a `Piece` — it's a record of what
  happened, not something with its own behavior beyond describing a turn.

## Step 4: Design Decisions & Patterns Used

**Polymorphism / Strategy for movement rules — again.** Just like the
`Vehicle` hierarchy in the parking lot problem and the win-check in
Tic-Tac-Toe, the core decision here is: who owns the "how does this move"
logic? The naive design puts a `piece_type` enum on a single `Piece` class
and a `case piece_type` inside `Board#valid_moves_for(piece)`. That fails
Open/Closed immediately — every new special rule for one piece (say, "the
knight is a poisoned trap and can't be captured" in some variant) forces
you back into that one giant method, and worse, the method has to know
about board-blocking rules for sliding pieces (rook/bishop/queen) *and*
special pawn capture-only-diagonally rules *and* knight's L-jump-that-
ignores-blocking, all tangled together. Instead, each subclass implements
`valid_moves(board)` for itself: `Rook` walks in four directions until
blocked, `Knight` enumerates eight fixed offsets with no blocking check at
all, `Pawn` special-cases forward-move-vs-diagonal-capture internally.
`Board` and `Game` never know these rules exist — they just call
`piece.valid_moves(board)` and get a list back. This is the Strategy
pattern (or, read differently, just correct use of polymorphism over a
type-switch) applied to movement.

**Why check/checkmate detection is a simulate-then-verify algorithm, not
a special rule per piece.** "Is the king in check" is answered generically:
compute the set of squares attacked by every opposing piece (union of each
opposing piece's `valid_moves`, including captures), and check whether the
king's own position is in that set. This works uniformly for all pieces
because attacked-squares is built entirely from the already-polymorphic
`valid_moves`. "Is this move legal" then becomes: tentatively apply the
move on a scratch copy of the board, check `in_check?(mover's own color)`
on that scratch board, and reject the move if it's still true — this
directly implements "you cannot move into (or leave yourself in) check"
without writing any pin/discovered-check-specific logic; it falls out of
simulate-then-check-attacked-squares for free. **Checkmate** is then: the
king is currently in check, AND there is no legal move — across *all* of
the player's pieces, not just the king — that resolves it. This means
checkmate detection literally reuses "try every legal move and see if any
one leaves the king safe," i.e. it's built directly on the same simulation
primitive, not a separate algorithm.

**Why `Move` is its own object instead of just calling
`board.move_piece(from, to)` and forgetting about it.** Same rationale as
`ParkingTicket` in the parking lot problem and, more directly, the
`Transaction` object pattern used for ATM-style command history: capturing
from/to/piece/captured-piece per turn gives you move history for free,
which is what undo and "replay this game" are built on. Without a `Move`
list, undo would require reconstructing "what was captured here" from
nothing, which isn't generally recoverable.

**Naive alternative, explicitly rejected**: one `Piece` class with a
`type` symbol and all movement logic centralized in `Board` via a type
switch. It's less code up front but makes every one of check-detection,
checkmate-detection, and "add a new piece" measurably harder, because none
of them can be built generically on top of a uniform `valid_moves`
interface.

## Step 5: Code

Not every piece needs a full implementation to prove the pattern — `Pawn`
(the most irregular piece: direction-dependent, capture differs from
advance) and `Knight` (fixed-offset, ignores blocking entirely) are shown
in full; the others follow the same shape (`Rook`/`Bishop`/`Queen` are
"walk in a set of directions until blocked or off-board").

```ruby
Position = Struct.new(:row, :col) do
  def in_bounds? = row.between?(0, 7) && col.between?(0, 7)
  def +(other) = Position.new(row + other.row, col + other.col)
end

class Piece
  attr_reader :color
  attr_accessor :position

  def initialize(color, position)
    @color = color
    @position = position
  end

  # Returns legal destination Positions, ignoring "does this leave my own
  # king in check" — that check happens one layer up, in Game, since it
  # requires simulating a move on the whole board, not just this piece.
  def valid_moves(board)
    raise NotImplementedError, "#{self.class} must implement valid_moves"
  end

  def symbol
    raise NotImplementedError
  end

  def enemy?(other_piece) = other_piece && other_piece.color != color
end

class Pawn < Piece
  def valid_moves(board)
    moves = []
    dir = color == :white ? -1 : 1          # white advances toward row 0
    start_row = color == :white ? 6 : 1
    one_step = Position.new(position.row + dir, position.col)

    if one_step.in_bounds? && board.piece_at(one_step).nil?
      moves << one_step
      two_step = Position.new(position.row + 2 * dir, position.col)
      moves << two_step if position.row == start_row && board.piece_at(two_step).nil?
    end

    [-1, 1].each do |dc|
      capture_pos = Position.new(position.row + dir, position.col + dc)
      next unless capture_pos.in_bounds?
      target = board.piece_at(capture_pos)
      moves << capture_pos if enemy?(target)
      # En passant would be added here as an explicit special-case check
      # against the game's last move, not folded into this loop silently.
    end

    moves
  end

  def symbol = color == :white ? "P" : "p"
end

class Knight < Piece
  OFFSETS = [[-2, -1], [-2, 1], [-1, -2], [-1, 2],
             [1, -2], [1, 2], [2, -1], [2, 1]].freeze

  def valid_moves(board)
    OFFSETS.filter_map do |dr, dc|
      dest = Position.new(position.row + dr, position.col + dc)
      next unless dest.in_bounds?

      target = board.piece_at(dest)
      dest if target.nil? || enemy?(target)   # no blocking check — knight jumps
    end
  end

  def symbol = color == :white ? "N" : "n"
end

class SlidingPiece < Piece
  # Shared skeleton for Rook/Bishop/Queen: walk each direction until
  # blocked by a piece (stop, including the capture square if it's an
  # enemy) or the board edge.
  def sliding_moves(board, directions)
    directions.flat_map do |dr, dc|
      moves = []
      step = Position.new(position.row + dr, position.col + dc)
      while step.in_bounds?
        target = board.piece_at(step)
        if target.nil?
          moves << step
        else
          moves << step if enemy?(target)
          break
        end
        step = Position.new(step.row + dr, step.col + dc)
      end
      moves
    end
  end
end

class Rook < SlidingPiece
  DIRECTIONS = [[-1, 0], [1, 0], [0, -1], [0, 1]].freeze
  def valid_moves(board) = sliding_moves(board, DIRECTIONS)
  def symbol = color == :white ? "R" : "r"
end

class Bishop < SlidingPiece
  DIRECTIONS = [[-1, -1], [-1, 1], [1, -1], [1, 1]].freeze
  def valid_moves(board) = sliding_moves(board, DIRECTIONS)
  def symbol = color == :white ? "B" : "b"
end

class Queen < SlidingPiece
  DIRECTIONS = (Rook::DIRECTIONS + Bishop::DIRECTIONS).freeze
  def valid_moves(board) = sliding_moves(board, DIRECTIONS)
  def symbol = color == :white ? "Q" : "q"
end

class King < Piece
  OFFSETS = [-1, 0, 1].product([-1, 0, 1]) - [[0, 0]]

  def valid_moves(board)
    # Castling is deliberately NOT included here — it depends on whether
    # the king/rook have ever moved and whether squares between them are
    # attacked, which needs Game-level history. It's added as an explicit
    # extra candidate move in Game#legal_moves_for, not silently merged
    # into this method.
    OFFSETS.filter_map do |dr, dc|
      dest = Position.new(position.row + dr, position.col + dc)
      next unless dest.in_bounds?

      target = board.piece_at(dest)
      dest if target.nil? || enemy?(target)
    end
  end

  def symbol = color == :white ? "K" : "k"
end

class Board
  def initialize
    @grid = Array.new(8) { Array.new(8) }
  end

  def piece_at(position) = @grid[position.row][position.col]

  def place(piece, position)
    piece.position = position
    @grid[position.row][position.col] = piece
  end

  def move_piece(from, to)
    piece = piece_at(from)
    captured = piece_at(to)
    @grid[from.row][from.col] = nil
    @grid[to.row][to.col] = piece
    piece.position = to
    captured
  end

  def all_pieces(color = nil)
    @grid.flatten.compact.select { |p| color.nil? || p.color == color }
  end

  def king_position(color)
    all_pieces(color).find { |p| p.is_a?(King) }.position
  end

  # Union of every attacking piece's valid_moves — the generic basis for
  # check detection described in Step 4.
  def attacked_squares(by_color)
    all_pieces(by_color).flat_map { |piece| piece.valid_moves(self) }.uniq
  end

  def in_check?(color)
    attacked_squares(opposite(color)).include?(king_position(color))
  end

  # Deep-ish copy sufficient for simulating a move: new Board, new piece
  # instances with the same color/position, so mutating the clone never
  # touches the real game state.
  def deep_dup
    clone = Board.new
    all_pieces.each { |p| clone.place(p.class.new(p.color, p.position), p.position) }
    clone
  end

  private

  def opposite(color) = color == :white ? :black : :white
end

Move = Struct.new(:from, :to, :piece, :captured_piece)

class Game
  attr_reader :board, :current_turn, :move_history

  def initialize
    @board = Board.new
    setup_standard_position
    @current_turn = :white
    @move_history = []
  end

  # Returns :ok, :check, :checkmate, or :illegal.
  def move(from, to)
    piece = board.piece_at(from)
    return :illegal if piece.nil? || piece.color != current_turn
    return :illegal unless legal_moves_for(piece).include?(to)

    captured = board.move_piece(from, to)
    move_history << Move.new(from, to, piece, captured)
    switch_turn

    return :checkmate if checkmate?(current_turn)
    return :check if board.in_check?(current_turn)

    :ok
  end

  # A piece's raw valid_moves, filtered to exclude any move that would
  # leave the mover's OWN king in check — this is the simulate-then-verify
  # step described in Step 4.
  def legal_moves_for(piece)
    piece.valid_moves(board).select do |dest|
      scratch = board.deep_dup
      scratch.move_piece(piece.position, dest)
      !scratch.in_check?(piece.color)
    end
  end

  def checkmate?(color)
    return false unless board.in_check?(color)

    board.all_pieces(color).all? { |piece| legal_moves_for(piece).empty? }
  end

  def stalemate?(color)
    return false if board.in_check?(color)

    board.all_pieces(color).all? { |piece| legal_moves_for(piece).empty? }
  end

  private

  def switch_turn
    @current_turn = current_turn == :white ? :black : :white
  end

  def setup_standard_position
    back_rank = [Rook, Knight, Bishop, Queen, King, Bishop, Knight, Rook]
    back_rank.each_with_index do |klass, col|
      board.place(klass.new(:white, Position.new(7, col)), Position.new(7, col))
      board.place(klass.new(:black, Position.new(0, col)), Position.new(0, col))
    end
    8.times do |col|
      board.place(Pawn.new(:white, Position.new(6, col)), Position.new(6, col))
      board.place(Pawn.new(:black, Position.new(1, col)), Position.new(1, col))
    end
  end
end
```

## Step 6: Edge Cases & Extensibility

- **Moving into check**: handled generically by `legal_moves_for`'s
  simulate-then-`in_check?` filter — this also covers the subtler "pinned
  piece" case (a piece that isn't the king but moving it would expose the
  king) automatically, since the simulation checks the resulting board
  state regardless of *which* piece moved.
- **Pawn promotion**: when a pawn reaches the far rank, `Game#move` should
  detect `to.row == 0 || to.row == 7` for a pawn and replace it with a
  player-chosen piece (usually a Queen) — a small explicit branch in
  `move`, not something `Pawn#valid_moves` should try to handle itself,
  since "what to promote to" is a player decision, not a movement rule.
- **Castling**: requires tracking whether the king and the relevant rook
  have ever moved (add a `moved` flag to `Piece`, flipped in
  `move_piece`), plus verifying the squares between them are empty and not
  attacked. Flag this explicitly as "I'd implement this as an extra
  candidate move injected in `Game#legal_moves_for` for the king, layered
  on top of the base system, given more time" — being upfront about this
  under interview time pressure is the right move, not a weakness.
- **En passant**: requires knowing the *previous* move (a pawn that just
  advanced two squares can be captured en passant on the very next turn
  only) — this is exactly why `move_history` exists on `Game` rather than
  nowhere; the rule reads `move_history.last` to decide legality. Same
  honesty applies: name it as a targeted extension, don't fake having it.
- **A move that isn't this player's turn, or moves an empty square /
  opponent's piece**: `Game#move` checks `piece.nil? || piece.color !=
  current_turn` up front and returns `:illegal` before ever touching
  `Board`.

## Follow-up Questions an Interviewer Might Ask

1. **"How do you tell stalemate from checkmate?"** Both check "does this
   color have zero legal moves across all pieces" — the only difference is
   whether the king is currently in check (`checkmate?`) or not
   (`stalemate?`). The code above makes this explicit: both methods share
   the same "no legal moves" core and just branch on `in_check?` first.
2. **"How would you support undo / game replay?"** `move_history` is a
   list of `Move` objects with `from`, `to`, `piece`, and
   `captured_piece` — undo pops the last entry, moves `piece` back to
   `from`, and restores `captured_piece` (if any) to `to`. This is the
   same Command-pattern-flavored benefit called out for `ParkingTicket` in
   the parking lot problem and for `Move` here: capturing enough state at
   the time of the action to reverse it later, instead of trying to
   reconstruct it afterward.
3. **"Isn't `deep_dup` + full re-simulation for every candidate move
   expensive?"** Yes — for a mid-game position with many pieces, checking
   legality for every candidate move of every piece is O(pieces ×
   candidate moves × board copy cost) per turn, more if you're computing
   full `legal_moves_for` for every piece to test checkmate. A common
   real-engine optimization is incremental "is my king currently pinned
   along this line" bookkeeping instead of a full board copy per candidate
   — worth naming as the natural next optimization, mirroring the
   incremental-counter idea used for Tic-Tac-Toe's win detection.
4. **"How would you validate this against real chess notation (PGN/FEN)?"**
   `Position` would need a `to_algebraic`/`from_algebraic` conversion
   (`Position.new(0,4)` ↔ `"e8"`), and `Board` would need a serializer to
   and from FEN strings — neither touches the movement-rule classes at
   all, which is a good sign the layering is right.
5. **"How would you add a new chess variant piece, like a 'Wizard' that
   moves like a bishop but can jump one piece?"** Add `class Wizard <
   Piece` implementing its own `valid_moves` — zero changes to `Board`,
   `Game`, or any other piece, which is the Open/Closed payoff the whole
   design was built around.
6. **"How would you detect a draw by repetition or the 50-move rule?"**
   Both are cheap additions given `move_history`: repetition needs a
   history of board-position hashes (store a hash of the board state after
   each move, flag a draw if the same hash appears 3 times); the 50-move
   rule just counts moves since the last pawn move or capture, both of
   which are already visible on each `Move` entry.
