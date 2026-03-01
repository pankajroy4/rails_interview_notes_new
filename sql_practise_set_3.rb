1:Open Postgres Sql console:
    psql -U postgres
2:create DataBase: (If do not have already)
    CREATE DATABASE sql_interview_lab;
3:Switch to database:
    \c sql_interview_lab;    
4:Create Tables:

  CREATE TABLE pattern_users (
      id BIGSERIAL PRIMARY KEY,
      name VARCHAR(100),
      email VARCHAR(150),
      username VARCHAR(100),
      bio TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

5:Insert Data:
    INSERT INTO pattern_users (name, email, username, bio, created_at) VALUES
    ('Pankaj', 'pankaj@gmail.com', 'Pan_123', 'Backend Developer', NOW()),
    ('Panama', 'panama@yahoo.com', 'Panama01', 'Lives in Mumbai', NOW()),
    ('Puneet', 'puneet@company.com', 'Puneet_dev', 'Loves PostgreSQL', NOW()),
    ('Pinak', 'pinak@abc.com', 'Pin_ak', 'Regex enthusiast', NOW()),
    ('Punam', 'punam@gmail.com', 'Punam99', 'Testing _ wildcard', NOW()),
    ('panther', 'panther@gmail.com', 'panther%', 'Contains percent % symbol', NOW()),
    ('PANDEY', 'pandey@company.com', 'PAND_01', 'Uppercase name', NOW()),
    ('Kumar', 'kumar@gmail.com', 'kumar_dev', 'Ends with kumar', NOW()),
    ('Rahul1', 'rahul1@gmail.com', 'rahul_1', 'Contains digit 1', NOW()),
    ('Rohit22', 'rohit22@yahoo.com', 'rohit_22', 'Two digits at end', NOW()),
    ('Ankit%', 'ankit%test@gmail.com', 'ankit_percent', 'Special % char', NOW()),
    ('User_One', 'user_one@test.com', 'user_one', 'Has underscore', NOW()),
    ('  PanTest  ', 'pantest@sample.com', 'pantest', 'Leading and trailing spaces', NOW()),
    ('abc', 'abc@abc.com', 'abc', 'Simple abc user', NOW()),
    ('Paa', 'paa@short.com', 'paa', 'Three letter name', NOW()),
    ('Pbc', 'pbc@test.com', 'pbc', 'Three letter name', NOW()),
    ('Pnnn', 'pnnn@test.com', 'pnnn', 'Four letters starting P', NOW()),
    ('Pa', 'pa@test.com', 'pa', 'Too short', NOW()),
    (NULL, 'nullname@test.com', 'null_user', 'Null name example', NOW());

6:Create Indexes for Performance Testing:
  🔸Normal B-tree index
      CREATE INDEX idx_pattern_users_name ON pattern_users(name);
  🔸Functional index for ILIKE
    CREATE INDEX idx_pattern_users_lower_name 
    ON pattern_users (LOWER(name));
  🔸Trigram index for contains/suffix search
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE INDEX idx_pattern_users_name_trgm
    ON pattern_users USING gin (name gin_trgm_ops);

============================================= PRACTICE QUESTIONS =============================================

LIKE / ILIKE
------------
1.Find users whose name starts with Pan.
2.Find users whose name ends with mar.
3.Find users whose name contains abc.
4.Find users whose name is exactly 3 characters long and starts with P.
5.Find users whose second character is a.
6.Find usernames that contain literal % character.
7.Find usernames that contain literal _ character.
8.Find names case-insensitive starting with pan.
9.Find users whose name has at least 4 characters and starts with P.
10.Find names that start with P and have exactly 4 characters.

Escaping
--------
11.Find users whose name literally contains %
12.Find users whose name literally contains _
13.Find users whose bio contains _ symbol

Regex Basic
-----------
14.Find users whose name contains at least one digit.
15.Find users whose name contains only alphabets.
16.Find names that start with P and end with t.
17.Find names that start with P and are 3 to 6 characters long.
18.Find names that do NOT contain any digit.
19.Find names that contain at least two consecutive digits.
20.Find names that are entirely uppercase.

Advanced Regex
--------------
21.Find emails from gmail domain only.
22.Find emails from gmail or yahoo.
23.Find usernames that end with digit.
24.Find usernames starting with letter and ending with number.
25.Find names with leading/trailing spaces.
26.Find names containing repeated characters like nn.
27.Find names that contain at least one vowel.
28.Find emails with invalid format (missing @ or dot).

Performance + Index Thinking
---------------------------
29.Run EXPLAIN ANALYZE on:
    SELECT * FROM pattern_users
    WHERE name LIKE 'Pan%';

    Does it use index?

30.Run EXPLAIN ANALYZE on:
    SELECT * FROM pattern_users
    WHERE name LIKE '%mar';

    Why is it slow?

31.Run EXPLAIN ANALYZE on:
    SELECT * FROM pattern_users
    WHERE name ILIKE 'pan%';

    Does it use functional index?

32.Run EXPLAIN ANALYZE on:
    SELECT * FROM pattern_users
    WHERE name LIKE '%an%';

    Does trigram index get used?

Hard
-----
33.Find names matching pattern:
    Starts with P
    Contains exactly one digit
    Ends with digit

34.Find emails where local part (before @) has underscore.
35.Find usernames where number appears exactly twice.
36.Find names that are palindrome.
37.Find users whose name has at least 2 vowels.
38.Find usernames where _ appears exactly once.
39.Find names that contain 3 consecutive letters.
40.Find names where first and last letter are same.