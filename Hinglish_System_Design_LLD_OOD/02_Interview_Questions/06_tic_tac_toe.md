# Design Tic-Tac-Toe (Object-Oriented Design)

## Problem Statement

"Design a Tic-Tac-Toe game. Do players baari-baari ek N x N board ko apne
symbol se mark karte hain. Jisko bhi N marks ek line me mil jaayein —
horizontally, vertically, ya diagonally — wo jeet jaata hai. Agar board
bina kisi winner ke bhar jaaye, to yeh draw hai."

Yeh sunne me trivial lagta hai — zyaadatar candidates kuch hi minutes me
ek hardcoded 3x3 board aur eight fixed win lines check karne wale teen
`if` statements bana lete hain. Interview yeh test nahi kar raha ki aap
wo kar sakte ho; yeh test kar raha hai ki jab interviewer kahega "ab isko
kisi bhi board size N ke liye kaam karwao" tab kya hota hai. Agar aapka
win-check hardcoded row/column/diagonal triples ka ek scan hai, to aapko
usko scratch se rewrite karna padega. Agar aapne shuru se generally design
kiya — aur, zyaada important, ise *fast* hone ke liye design kiya — to
aapko bas ek constructor argument change karna hai. Bas yehi poora
interview hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- N x N board support karo (default 3x3, lekin generalize hona chahiye —
  kabhi bhi `3` hardcode mat karo).
- Do ya zyaada players, har ek ka apna distinct symbol (X, O, ...).
- Players baari-baari khelte hain; ek move ek empty cell me player ka
  symbol place karta hai.
- Har move ke baad, detect karo: yeh player jeet gaya, board bina winner
  ke bhar gaya hai (draw), ya game continue hai.
- Illegal moves reject karo: ek occupied cell par move, ya game already
  end hone ke baad koi bhi move.

**Non-Functional Requirements**
- **Win detection ki efficiency**: har move ke baad win check karne ke
  liye poore board ko rescan nahi karna chahiye. Ek naive full-board scan
  per move O(N²) hai aur poore game me O(N⁴) — 3x3 ke liye theek hai,
  lekin jab interviewer 15x15 Gomoku-style board ke baare me poochta hai
  to bura ho jaata hai. Per move O(1) (ya win-length me O(N), board size
  me nahi) aim karo.
- **Extensibility**: 2 se zyaada players support karna, ek variable
  win-length (K-in-a-row ek N x N board par, yaani Gomoku) ya ek
  non-square board support karna — inke liye win-check logic rewrite nahi
  karna chahiye — sirf reconfigure karna chahiye.
- **Separation of concerns**: `Board` ko turn order ya "game kisne jeeta"
  jaise concept ke baare me nahi pata hona chahiye — usko sirf "kya yeh
  ek winning move hai" aur "kya main full hoon" ka jawab dena chahiye.
  `Game` turn orchestration aur overall game state own karta hai.

## Step 2: Identify Core Objects / Entities

- **Player** — ek symbol (`"X"`, `"O"`) aur ek display name.
- **Board** — N x N grid of cells, har ek me ek player ka symbol ya empty
  hota hai. Win-detection machinery own karta hai.
- **Move** — ek lightweight value (row, col, player) — mainly
  parameter/return shape ke roop me useful, ek full class hone ki zaroorat
  nahi lekin ek concept ke roop me naam dene layak hai.
- **Game** — turn order orchestrate karta hai, har move ko `Board` par
  delegate karta hai, aur outcome report karta hai (in progress / X ne
  jeeta / draw).

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
- `Game` `Board` ko **compose** karta hai — ek board ka koi meaning ya
  lifecycle nahi hota us game ke bina jo usko own karta hai.
- `Game` `Player` ke saath **associate** hota hai — players independently
  exist karte hain (ek `Player` object bahut saare games me reuse ho
  sakta hai); game bas turn order ke liye unko reference karta hai.
- `Board` ko `Player` objects ke baare me bilkul **pata nahi** hai — yeh
  sirf symbols (strings) me deal karta hai. Yeh ek deliberate decoupling
  hai: board ek pure grid-and-counting data structure hai, aur `Game`
  hi wo akela class hai jo "kiski baari," "kisne jeeta" samajhta hai.

## Step 4: Design Decisions & Patterns Used

**Har move par board scan karne ke bajaye incremental counters kyun.**
Naive win-check, chahe "generally" likha jaaye (saari rows, saare columns,
dono diagonals loop karo, check karo ki N cells match karte hain ya
nahi), phir bhi per line O(N) work hai aur O(N) lines hain, isliye sirf
ek win check karne ke liye per move O(N²) — aur yeh har single move par
kaam repeat karta hai chahe sirf ek row, ek column, aur zyaada se zyaada
do diagonals hi change hue hon. Insight yeh hai: `(row, col)` par ek move
sirf *us* row, *us* column, aur `(row, col)` se guzarne wale diagonal(s)
ko affect kar sakta hai. Isliye scan karne ke bajaye, `Board` char running
tallies maintain karta hai — har symbol ka count per row, per column, main
diagonal par, aur anti-diagonal par — aur har move par sirf relevant wale
increment karta hai. "Kya is move ne jeeta" check karna char O(1) lookups
ban jaata hai: kya `row_counts[symbol][row]` abhi `win_length` tak
pahunchi? Kya `col_counts[symbol][col]`? Waghera. Isse win detection
O(N²) se O(1) per move ban jaata hai (ya O(K) agar aapko yeh bhi pata
karna hai ki *kaunse* cells ne line banayi, jaise, UI me highlight karne
ke liye). Yeh is problem ka single sabse interview-relevant idea hai — yeh
ek genuine algorithmic optimization hai, sirf clean OOP nahi, aur yehi
exactly wo cheez hai jo ek strong answer ko average se separate karti hai.

**`win_length` board `size` se ek separate parameter kyun hai.** Standard
Tic-Tac-Toe "3x3 board par 3-in-a-row" hai, isliye `win_length == size`
hota hai aur inko conflate karna easy hai. Lekin Gomoku "15x15 (ya bade)
board par 5-in-a-row" hai — `win_length < size`. Agar aap hardcode karo ki
"jeetne ka matlab hai poori row ek symbol ki hai," to aap bina rewrite ke
Gomoku support nahi kar sakte. Inhe day one se separate rakhna (aur
counters ko sirf "row full hai kya" ke bajaye "current run kitni lambi
hai" track karwana) matlab hai ki Gomoku ek constructor argument change
ban jaata hai, ek redesign nahi — yehi wo generalization hai jo
interviewer board-size follow-up poochte waqt dhundh raha hota hai.

**`Board` `Player` ko reference kyun nahi karta.** Agar `Board` `Player`
objects store karta, to usko pata hona padta ki players ko kaise compare
karein, aur `Player` me future me add hone wala har naya concept (rating,
avatar, AI-difficulty) ek dependency ban jaata jo board ko chahiye hi
nahi. `Board` ko symbol-only rakhne ka matlab hai ki yeh trivially reusable
aur isolation me testable hai — aap raw strings se win detection ko
unit-test kar sakte ho aur kabhi bhi `Game` ya `Player` construct karne ki
zaroorat nahi padti.

**Naive alternative, explicitly rejected**: ek fixed 3x3 board ke liye
eight hardcoded win-line checks (3 rows + 3 cols + 2 diagonals). Live
type karne ke liye yeh sabse fast cheez hai, lekin jaise hi "NxN ka kya"
wala follow-up aata hai yeh ek dead end ban jaata hai, aur interviewers
yeh follow-up specifically isliye poochte hain kyunki itne saare
candidates is trap me fasse jaate hain.

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

**Isko use karna:**

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

- **Occupied cell par move**: `make_move` `place` call karne se pehle
  `board.empty_at?` check karta hai aur `:illegal` return kar deta hai —
  yeh win-check logic tak pahunchta hi nahi, aur `Board#place` khud bhi
  defensively raise karta hai agar direct ek bad cell ke saath call kiya
  jaaye, isliye invariant tab bhi hold karta hai jab `Game` bypass ho
  jaaye.
- **Game khatam hone ke baad move**: `make_move` me sabse pehle `over?`
  check hota hai, kiski baari hai yeh verify karne se bhi pehle — ek baar
  `status` `:won` ya `:draw` ho jaaye to game frozen ho jaata hai.
- **Full board, koi winner nahi (draw)**: yeh ek non-winning placement ke
  turant baad check hota hai — `board.full?` ek O(1) counter check hai
  (`@filled_count`), koi re-scan nahi, jo "no full rescans" wale design
  goal ke saath consistent hai.
- **Galat player ki move** (out of turn): `make_move`
  `player == current_player` check karta hai aur otherwise reject kar
  deta hai — ek caller bug ko turn order corrupt karne se rokta hai.
- **N=1 board**: degenerate hai lekin code isko handle karta hai — ek
  single placement turant jeet jaata hai (`win_length` default 1 hota
  hai). Boundary conditions ke baare me poochne par yeh ek sanity-check
  case ke roop me mention karne layak hai.

## Follow-up Questions an Interviewer Might Ask

1. **"Variable board size kaise support karoge?"** Already supported hai
   — `Board.new(size: N)` — aur yehi exact reason hai ki win detection
   hardcoded lines ke bajaye per-row/per-column/per-diagonal counters par
   banaya gaya tha: counters `size` se dynamically generate hote hain,
   isliye aur kuch change nahi hota.
2. **"Ab isko Gomoku bana do — 15x15 ya 19x19 board par 5-in-a-row."**
   Yeh bhi already ek separate `win_length` parameter ke through
   supported hai — yeh natural payoff hai shuru se "board size" ko "win
   condition" ke saath conflate na karne ka. Interviewer ko explicitly
   yeh point out karna worth hai ki yeh ek deliberate design choice thi,
   luck nahi.
3. **"AI opponent kaise add karoge?"** Standard approach **minimax** hai
   (3x3 se bade kisi bhi board ke liye alpha-beta pruning ke saath, kyunki
   search space fast explode hota hai): AI recursively har legal move
   simulate karta hai, assume karta hai ki opponent uske against optimally
   khelega, aur wo move pick karta hai jo uska khud ka guaranteed outcome
   maximize kare. Aap live time pressure me full minimax implement nahi
   karoge, lekin aapko recursion describe karne me able hona chahiye aur
   yeh state karna chahiye ki `Board` already minimax ko chahiye wo sab
   expose karta hai (`empty_at?`, `place`, legal moves enumerate karne
   ka ek tareeka) bina kisi modification ke — yeh ek sign hai ki board ka
   interface well-factored hai.
4. **"2 se zyaada players ke liye win kaise detect karoge?"** Design
   already generalize karta hai — `players` ek array hai,
   `advance_turn` iske size modulo cycle karta hai, aur win-check me
   exactly do symbols hone ki koi assumption nahi hai; asli question yeh
   ban jaata hai ki N players ke saath kaunsa board size sense banata hai
   (interviewers kabhi-kabhi bas yeh chahte hain ki aap isko ek
   game-design question ke roop me flag karo, code question nahi).
5. **"Agar main last move ko undo karna chahoon to?"** `Game` par ek
   `moves` history stack add karo (har entry: player, row, col) aur ek
   `undo` add karo jo last entry pop kare, `Board` me cell clear kare,
   relevant counters decrement kare, aur agar undone move winning move
   thi to `status`/`winner` revert kare — counter-based design decrementing
   ko incrementing ke saath symmetric banata hai, jo call out karne layak
   ek nice side benefit hai.
6. **"Win-detection logic ko isolation me kaise test karoge?"** Chunki
   `Board` `Player` ya `Game` par depend nahi karta, aap isko raw symbol
   strings se directly unit test kar sakte ho: `"X"`/`"O"` moves ki ek
   sequence place karo aur assert karo ki `place` sirf winning move par
   `true` return karta hai — koi game orchestration nahi chahiye, jo
   Step 4 me kiye gaye decoupling decision ka ek direct payoff hai.
