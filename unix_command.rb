=============================  Basic structure understanding  ==============================
➤ In LINUX commands, the symbol - is used to pass options (flags) to a command.
  Syntax: command -options arguments

➤Short flags (single dash -)
    rm -r
    rm -f
    ls -l

  Here, Each letter is a separate option.
  we can combine them.
    rm -rf tmp/cache

    This is same as:
      rm -r -f tmp/cache

➤Long flags (double dash --)
  It is more descriptive. Examples:
    ls --all
    rm --recursive

  Here:
    rm -r folder
    rm --recursive folder
  Both mean same.

➤Double dash alone --
  It means: "Stop parsing options after this."
  Used when filename starts with -
    example:
      rm -- -file.txt
    Here, if we do not use -- then system thinks -file.txt is a flag.


============================================================================================================
🔸File System commands:
  🔹ls 
    It wil list files and folders names only.

  🔹ls -la 
      l → long listing (permissions, owner, size, timestamp)
      a → include hidden files (dot files like .env, .gitignore)

      Output shows:
        File permissions
        Number of links
        Owner & group
        Size
        Modified date

      First character in output means:
        - file, d directory, l symlink.
  🔹cd
    Used to change directory
      cd /var/www/app
      cd ..   This will go to parent directory
      cd ~    This will go to home directory

  🔹pwd
    Print working directory in console.
    Useful in scripts and debugging relative paths.

  🔹mkdir
    Create directory.
      mkdir test
      mkdir -p app/controllers/admin

      p  This falg will create parent directories if not exist.

  🔹rm -rf
    It is used to delete directories including contents.

    r   means recursive(delete directories)
    f   means force (no confirmation)

    example:
      rm -rf tmp/cache

    Difference between rm -r and rm -rf?
    Ans:  f skips confirmation and ignores non-existing files.

  🔹cp
    Copy files or directories.
      examples:
        cp file.txt backup.txt
        cp -r folder1 folder2

     -r  means recursive (for directories)
  
  🔹mv
    Move or rename files.
    examples:
      mv old.txt new.txt
      mv file.txt /tmp/

  🔹touch
    Create empty file or update timestamp. example: touch test.rb

---------------------------------------------------------------------------------------------------------------
🔸Permissions based commands:
  chmod 755 file
  chown user:group file

  What is 755?
    Owner: read, write, execute
    Group: read, execute
    Others: read, execute

Process Management commands:
  ps aux
  top
  htop
  kill -9 PID
  jobs
  bg
  fg

Networking commands:
  netstat -tulpn
  lsof -i :3000
  curl
  ping

Logs commands:
  tail -f log/production.log
  grep "ERROR" file.log

Disk & Memory based commands:
  df -h
  du -sh
  free -m



Question: Production is slow. What will you check?

Answer:
CPU usage → top
Memory → free -m
Disk → df -h
Logs → tail -f
DB connections












=======================


Got it — lets slow it down and make it super simple 🙂

When you run:

chmod 755 file

You are telling Linux:

“Set permissions for this file using the number 755.”

Step 1: Files Have 3 Permission Groups

Every file has permissions for three types of users:

Owner → the person who owns the file

Group → users in the same group

Others → everyone else

So when you see:

755

It actually means:

7   5   5
│   │   │
│   │   └── Others
│   └────── Group
└────────── Owner
Step 2: What Do the Numbers Mean?

Each number is made from adding:

Number	Permission
4	Read (r)
2	Write (w)
1	Execute (x)

You add them together.

What is 7?
7 = 4 + 2 + 1

So 7 means:

rwx

(Read, Write, Execute)

What is 5?
5 = 4 + 1

So 5 means:

r-x

(Read, Execute — but NO write)

Step 3: So What Does 755 Mean?
Owner  → 7 → rwx
Group  → 5 → r-x
Others → 5 → r-x

That means:

The owner can read, edit, and run the file

Everyone else can read and run it

But only the owner can modify it

Real Example

If it is a script:

script.sh

And you run:

chmod 755 script.sh

Now:

You (owner) can edit it

Others can run it

Others cannot change it

Why chmod +x bin/rails?

That command just adds execute permission.

+x means:

“Allow this file to be run like a program.”

Without execute permission, you can’t run a file like:

./bin/rails
Quick Visual

Before:

-rw-r--r--

After chmod 755 file:

-rwxr-xr-x

See how:

Owner has rwx

Others have r-x

