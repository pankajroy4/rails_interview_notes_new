# Design Chess (Object-Oriented Design)

## Problem Statement

"Ek chess game design karo. Board, pieces aur unke movement rules model
karo, aur core game loop bhi — check aur checkmate detect karna bhi
included hai. Har special rule (castling, en passant, promotion) ko poori
tarah implement karna zaroori nahi hai, lekin batao ki pieces ko kaise
model karoge ki naya rule add karne se har doosre piece ka code touch na
karna pade."

Chess LLD interviews ka classic "polymorphism stress test" hai. Six piece
types hain, har ek ke genuinely alag movement rules hain, plus kuch global
rules (check, checkmate, check mein move karna illegal hai) jo sabpe
uniformly apply hote hain. Jo candidates struggle karte hain, wo aise hote
hain jo ek single `Piece` class banate hain with a `type` field aur ek
giant `case piece_type` `Board#valid_moves` ke andar. Jo candidates achha
karte hain, wo har piece ko apna `valid_moves` method dete hain aur board
aur game ko ignorant rehne dete hain ki bishop hota kya hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- Ek 8x8 board of squares; har square optionally ek piece hold karta hai.
- Six piece types (Pawn, Rook, Knight, Bishop, Queen, King), har ek apna
  legal-move pattern rakhta hai.
- Do players (White, Black) turns alternate karte hain; ek move sirf uss
  player ke liye legal hai jiski turn hai, apna khud ka piece move karte
  hue.
- Ek move jo opposing piece capture kare, use board se remove karti hai.
- **Check** detect karo (ek player ka king attack ke under hai),
  **checkmate** (check mein hai aur koi legal move nahi hai jo usse escape
  kare), aur — agar time permit kare — **stalemate** (check mein nahi hai,
  lekin koi legal move bilkul bhi nahi hai).
- Ek move jo moving player ke apne king ko check mein daal de, wo illegal
  hai (aap "check mein move" nahi kar sakte, chahe block ya capture karne
  ke liye ho).

**Non-Functional Requirements**
- **Extensibility**: kisi piece ka movement rule add ya modify karna sirf
  uss piece ki class ko touch karna chahiye — kabhi `Board` ya `Game` ko
  nahi.
- **Auditability**: game ko move history produce karne ke capable hona
  chahiye (undo, replay, ya "abhi tak ka game dikhao" ke liye) baad mein
  bolt-on kiye bina.
- **Honesty about scope**: castling, en passant, aur pawn promotion asli
  special-case rules hain jo base movement system ke upar layer hote hain,
  chupke se skip karne wali cheez nahi — explicitly batao ki inhe kaise add
  karoge, yeh pretend karne ke bajaye ki base design already inhe cover
  karta hai.

## Step 2: Identify Core Objects / Entities

- **Position** — ek square ke coordinates ke liye value object (row, col,
  ya algebraic notation jaise `"e4"`); immutable, comparable, hashable.
- **Piece** (abstract) → `Pawn`, `Rook`, `Knight`, `Bishop`, `Queen`,
  `King` — har ek apna `valid_moves(board, position)` khud own karta hai.
- **Square** — board ka ek cell; max ek `Piece` hold karta hai.
- **Board** — 8x8 grid of `Square`s; answer deta hai "is position pe kya
  hai," "kya yeh position color X ke attack ke under hai."
- **Move** — ek turn ke liye from/to/piece/captured-piece capture karta
  hai — yeh wahi object hai jo move history, undo, aur simulation-se-
  check-detection sab ko tractable banata hai, bilkul waise hi jaise
  parking lot problem mein `ParkingTicket` ne multi-spot release ko
  tractable banaya tha.
- **Player** — color (White/Black) plus identity.
- **Game** — turns orchestrate karta hai, `Board` ko call karke moves
  validate aur apply karta hai, move history track karta hai, aur
  check/checkmate detection ka owner hai.

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
- `Pawn`/`Rook`/`Knight`/`Bishop`/`Queen`/`King` `Piece` se **inherit**
  karte hain (is-a) — yahi is poore design ka crux hai.
- `Board` `Square`s ko **compose** karta hai, aur har `Square` max ek
  `Piece` ke saath **associate** hota hai (ek piece squares ke beech move
  kar sakta hai; iska lifecycle kisi ek square ka owned nahi hota).
- `Game` `Board` aur uski `move_history` (ek `Move` list) ko **compose**
  karta hai; yeh `Player`s ke saath **associate** hota hai.
- `Move` `Position`s aur ek `Piece` ko associate karta hai — yeh sirf
  ek record hai ki kya hua, describe karne ke alawa iska koi apna behavior
  nahi hai.

## Step 4: Design Decisions & Patterns Used

**Movement rules ke liye Polymorphism / Strategy — phir se.** Bilkul jaise
parking lot problem mein `Vehicle` hierarchy aur Tic-Tac-Toe mein win-check
tha, yahan core decision yeh hai: "yeh move kaise hota hai" logic ka owner
kaun hai? Naive design ek single `Piece` class pe `piece_type` enum daal
deta hai aur `Board#valid_moves_for(piece)` ke andar ek `case piece_type`
daal deta hai. Yeh Open/Closed principle ko turant fail karta hai — kisi
ek piece ke liye har naya special rule (maan lo, "kisi variant mein knight
poisoned trap hai aur capture nahi ho sakta") aapko wapas uss ek giant
method mein le jaata hai, aur worse yeh hai ki uss method ko sliding pieces
(rook/bishop/queen) ke liye board-blocking rules *aur* special pawn
capture-only-diagonally rules *aur* knight ke L-jump-jo-blocking-ignore-
karta-hai, sab kuch ek saath tangled hokar pata hona chahiye. Uski jagah,
har subclass apne liye `valid_moves(board)` implement karta hai: `Rook`
char directions mein tab tak chalta hai jab tak blocked na ho jaaye,
`Knight` eight fixed offsets enumerate karta hai bina koi blocking check
ke, `Pawn` forward-move-vs-diagonal-capture ko internally special-case
karta hai. `Board` aur `Game` ko in rules ke baare mein kabhi pata hi nahi
chalta — wo bas `piece.valid_moves(board)` call karte hain aur ek list
wapas milti hai. Yeh Strategy pattern hai (ya, differently padho toh, bas
movement ke liye type-switch ke bajaye polymorphism ka correct use hai).

**Check/checkmate detection ek simulate-then-verify algorithm kyun hai,
har piece ke liye ek special rule nahi.** "Kya king check mein hai" ka
answer generically diya jaata hai: har opposing piece ke attack kiye
squares ka set compute karo (har opposing piece ke `valid_moves` ka union,
captures included), aur check karo ki kya king ki apni position uss set
mein hai. Yeh sab pieces ke liye uniformly kaam karta hai kyunki
attacked-squares poori tarah already-polymorphic `valid_moves` se bana hai.
"Kya yeh move legal hai" phir yeh ban jaata hai: board ki ek scratch copy
pe tentatively move apply karo, uss scratch board pe `in_check?(mover's
own color)` check karo, aur agar wo abhi bhi true hai toh move reject kar
do — yeh directly "aap check mein move nahi kar sakte (ya khud ko check
mein chhod nahi sakte)" ko implement karta hai bina koi pin/discovered-
check-specific logic likhe; yeh simulate-then-check-attacked-squares se
free mein mil jaata hai. **Checkmate** phir yeh hota hai: king currently
check mein hai, AND koi bhi legal move nahi hai — player ke *saare*
pieces ke across, sirf king ke nahi — jo usse resolve kare. Iska matlab
checkmate detection literally "har legal move try karo aur dekho koi ek
king ko safe chhodta hai ya nahi" ko reuse karta hai, yaani yeh usi
simulation primitive pe built hai, ek separate algorithm nahi.

**`Move` apna khud ka object kyun hai instead of bas
`board.move_piece(from, to)` call karke bhool jaana.** Parking lot problem
mein `ParkingTicket` jaisa hi rationale hai, aur more directly, ATM-style
command history ke liye use hone wale `Transaction` object pattern jaisa:
har turn ke liye from/to/piece/captured-piece capture karna aapko move
history free mein deta hai, jispe undo aur "yeh game replay karo" built
hote hain. Bina `Move` list ke, undo ke liye "yahan kya capture hua tha"
ko nothing se reconstruct karna padta, jo generally recoverable nahi hai.

**Naive alternative, explicitly reject kiya gaya**: ek `Piece` class with
a `type` symbol aur saara movement logic `Board` mein centralized via type
switch. Upfront kam code hai lekin check-detection, checkmate-detection,
aur "naya piece add karna" — teeno ko measurably harder banata hai, kyunki
inme se koi bhi uniform `valid_moves` interface ke upar generically build
nahi ho sakta.

## Step 5: Code

Pattern prove karne ke liye har piece ka full implementation chahiye nahi
— `Pawn` (sabse irregular piece: direction-dependent, capture advance se
alag hai) aur `Knight` (fixed-offset, blocking ko poori tarah ignore karta
hai) poori tarah dikhaye gaye hain; baaki same shape follow karte hain
(`Rook`/`Bishop`/`Queen` "ek set of directions mein tab tak chalo jab tak
blocked ya off-board na ho").

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

- **Check mein move karna**: `legal_moves_for` ke simulate-then-`in_check?`
  filter se generically handle hota hai — yeh subtler "pinned piece" case
  (ek piece jo king nahi hai lekin usse move karna king ko expose kar
  dega) ko bhi automatically cover karta hai, kyunki simulation resulting
  board state check karta hai regardless of *kaunsa* piece move hua.
- **Pawn promotion**: jab ek pawn far rank tak pahunchta hai, `Game#move`
  ko `to.row == 0 || to.row == 7` detect karna chahiye ek pawn ke liye
  aur use player-chosen piece (usually Queen) se replace karna chahiye —
  `move` mein ek chhota explicit branch, kuch aisa nahi jo `Pawn#valid_moves`
  khud handle karne ki koshish kare, kyunki "kis mein promote karna hai"
  ek player decision hai, movement rule nahi.
- **Castling**: track karna padega ki king aur relevant rook kabhi move
  hue hain ya nahi (`Piece` pe ek `moved` flag add karo, `move_piece` mein
  flip hota hai), plus verify karna ki unke beech ke squares empty hain
  aur attacked nahi hain. Isse explicitly flag karo as "main isse
  `Game#legal_moves_for` mein king ke liye ek extra candidate move inject
  karke implement karunga, jo base system ke upar layered hoga, agar zyada
  time mile toh" — interview time pressure ke under isse upfront batana
  right move hai, weakness nahi.
- **En passant**: *previous* move jaanna zaroori hai (ek pawn jo abhi do
  squares advance hua hai, uske turant agle turn pe hi en passant capture
  ho sakta hai) — yahi wajah hai ki `move_history` `Game` pe hai kahin aur
  nahi; rule `move_history.last` padhta hai legality decide karne ke liye.
  Yahi honesty apply hoti hai: isse ek targeted extension bolo, isse hone
  ka natak mat karo.
- **Ek move jo is player ki turn nahi hai, ya empty square /
  opponent's piece move karta hai**: `Game#move` `piece.nil? ||
  piece.color != current_turn` upfront check karta hai aur `Board` ko
  touch kiye bina `:illegal` return karta hai.

## Follow-up Questions an Interviewer Might Ask

1. **"Stalemate ko checkmate se kaise differentiate karoge?"** Dono check
   karte hain "kya iss color ke paas saare pieces ke across zero legal
   moves hain" — sirf difference yeh hai ki king currently check mein hai
   (`checkmate?`) ya nahi (`stalemate?`). Upar wala code isse explicit
   banata hai: dono methods same "no legal moves" core share karte hain
   aur bas `in_check?` pe pehle branch karte hain.
2. **"Undo / game replay support kaise karoge?"** `move_history` `Move`
   objects ki ek list hai with `from`, `to`, `piece`, aur `captured_piece`
   — undo last entry pop karta hai, `piece` ko `from` pe wapas move karta
   hai, aur `captured_piece` (agar koi hai) ko `to` pe restore karta hai.
   Yeh wahi Command-pattern-flavored benefit hai jo parking lot problem
   mein `ParkingTicket` ke liye aur yahan `Move` ke liye call out kiya
   gaya hai: action ke time pe enough state capture karna baad mein reverse
   karne ke liye, baad mein reconstruct karne ki koshish karne ke bajaye.
3. **"Kya `deep_dup` + har candidate move ke liye full re-simulation
   expensive nahi hai?"** Haan — mid-game position mein jahan bahut saare
   pieces hote hain, har piece ke har candidate move ke liye legality
   check karna O(pieces × candidate moves × board copy cost) per turn
   hai, aur zyada agar checkmate test karne ke liye har piece ka full
   `legal_moves_for` compute kar rahe ho. Ek common real-engine
   optimization incremental "kya mera king abhi is line ke along pinned
   hai" bookkeeping hai instead of full board copy per candidate — worth
   naming karna as natural next optimization, Tic-Tac-Toe ke win
   detection mein use hone wale incremental-counter idea jaisa.
4. **"Isse real chess notation (PGN/FEN) ke against kaise validate
   karoge?"** `Position` ko ek `to_algebraic`/`from_algebraic` conversion
   chahiye (`Position.new(0,4)` ↔ `"e8"`), aur `Board` ko FEN strings se
   aur mein serializer chahiye — inme se koi bhi movement-rule classes ko
   touch nahi karta, jo ek good sign hai ki layering right hai.
5. **"Naya chess variant piece kaise add karoge, jaise ek 'Wizard' jo
   bishop jaisa move kare lekin ek piece jump kar sake?"** `class Wizard <
   Piece` add karo apne khud ke `valid_moves` ke saath — `Board`, `Game`,
   ya kisi bhi doosre piece mein zero changes, jo poore design ke around
   built Open/Closed payoff hai.
6. **"Repetition ya 50-move rule se draw kaise detect karoge?"** Dono
   `move_history` ke saath cheap additions hain: repetition ko
   board-position hashes ki history chahiye (har move ke baad board
   state ka hash store karo, agar same hash 3 baar aaye toh draw flag
   karo); 50-move rule bas last pawn move ya capture ke baad se moves
   count karta hai, dono already har `Move` entry pe visible hain.
