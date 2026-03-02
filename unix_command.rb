=============================  Basic structure understanding  ==============================
➤ In LINUX commands, the symbol - is used to pass options (flags) to a command. We can also pass multiple options by combining them.
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


=========================================== 🔸File System commands ====================================

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

=========================================== 🔸Process Management commands ====================================
🔸ps aux 
    What ps is: ps stands for process status.
    It lists the currently running processes on your system. Think of it as a snapshot of “what programs are running right now.”
    Example: ps alone might just show the processes running in your current terminal session.

    What aux is: These are cobinations of options/flags for ps.
      a → Show processes for all users, not just you.
      u → Display the user who owns each process, along with CPU/memory usage.
      x → Include processes that do not have a terminal attached (daemon/background processes like Puma).

    So ps aux gives you a full list of all running processes, including background services, along with details like PID, CPU/memory usage, and command.

    Examples: ps aux | grep puma
              ps aux | grep rails

    What is |: It is pipe.
      Purpose: Sends the output of the command on the left (ps aux) as input to the command on the right (grep puma).

    What grep is: grep stands for global regular expression print.
    Purpose: It searches text for lines matching a pattern.
    Example: grep puma looks through all the lines of output from ps aux and shows only lines containing puma.

    What puma is: Puma is the Rails web server.

    So in the command "ps aux | grep puma" we are filtering to see only processes related to the Puma server, e.g., to check if it is running, see its PID, or find memory usage.

    So,
      ps aux | grep puma means:
      “Show me all processes on the system, and then filter to only show the ones that have the word "puma" in them.”

🔹top
  it is used for real-time process monitor.
  Result shows:
    CPU usage
    Memory usage
    Running processes

🔹htop
  It is improved version of top (if installed). It show Colored UI and it offers interactive process kill. Also it provided better sorting.


🔹SIGTERM, SIGINT and SIGKILL:
    In Linux, processes communicate using signals — small messages sent to a process to tell it to do something.
    SIGTERM, SIGINT, SIGKILL etc are unix signal.
      +--------------------------------------------------------+
      | Signal  | Number | Can Be Trapped? | Behavior          |
      |---------|--------|-----------------|-------------------|
      | SIGTERM | 15     |      Yes        | Graceful shutdown |
      | SIGINT  | 2      |      Yes        | Ctrl+C            |
      | SIGKILL | 9      |      No         | Immediate death   |
      +--------------------------------------------------------+

    Processes (Puma, Sidekiq, etc) can normally catch a signal, handle it (run custom code) or ignore it.
    This is called trapping a signal.

    SIGTERM i.e 15 is the default signal sent by the kill command. SIGTERM signals can be trapped by a process.
      example: kill 1234 or kill -15 1234 or kill -SIGTERM 1234 => All three means same.

    SIGKILL i.e 9 means "Terminate immediately, Right now, No cleanup". It is force kill process. SIGKILL signals can not be trapped by any process.
      example: kill -9 1234 or  kill -SIGKILL 1234 or kill -KILL 1234 => All three means same.

    This is the reason, in production we should use SIGTERM i.e 15.
    example: kill -15 PID or simply kill pid
    This allow:
      Finish current request
      Close DB connections
      Save state
      Shut down gracefully

🔹kill -9 PID
  It is a Force kill process. This can not be trapped.

🔹jobs
    This command is used to List background jobs.
🔹bg
    This command is used to Resume job in background.
🔹fg
    This command is used to bring background job to foreground.
    Example:
      sleep 100 &
      jobs
      fg %1

🔹Multiline commands (\)
    When a command is too long, instead of writing everything on one line, we can split it for readability.
    The \ tells the shell: “This command continues on the next line. Do not execute yet.”
    NOTE: Backslash i.e (\) must be the last character on the line and no space after it.

    example: Long Docker command
          docker run -d \
            -p 3000:3000 \
            -e RAILS_ENV=production \
            my_rails_app

🔹Running command in background (&)
    When you put & at the end of a command example: rails server &
    It means: “Run this command in the background.”
    The terminal becomes free immediately.

🔹Run Next Command Only If Previous Succeeded (&&)
    example: bundle install && rails db:migrate

=========================================== 🔸Networking commands ====================================

🔹lsof
  This means "List Open Files"

  In Linux/Unix everything is treated like a file.
  That includes: Regular files, Directories, Network sockets, Devices, Pipes etc all are treated like a file.
  So lsof shows: Which process has which file open.

🔹lsof -i :3000
  It means: “List all processes that have a network connection (socket) open on port 3000.”

  Here, -i is the falg for Internet connections. 
  Here, -i tells lsof that show network-related files (Internet connections).
  So lsof -i means “Show all processes that are using network connections.”

🔹netstat -tulpn
  Here netstat stands for "Network Statistics"
  It shows:
    Network connections
    Listening ports
    Routing tables
    Interface statistics

  It is used to inspect what is happening at the networking level.
  On modern Ubuntu, netstat is considered legacy. ss is the newer replacement.

  The falg -tulpn means:
        +--------------------------------------------------------------------+
        | Flag |                     Meaning                                 |
        |------|-------------------------------------------------------------|
        |  -t  | Show TCP connections                                        |
        |  -u  | Show UDP connections                                        |
        |  -l  | Show only LISTENING sockets                                 |
        |  -p  | Show PID and program name                                   |
        |  -n  | Show numeric addresses (don’t resolve DNS or service names) |
        +--------------------------------------------------------------------+

  Example: netstat -tulpn | grep 3000

🔹curl
  It is used to make HTTP requests from terminal.
  Examples:
      curl http://localhost:3000         # GET request by default
      curl -X POST http://api.com        # POST request explicitly
      curl -X PUT http://api.com         # PUT request
      curl -X DELETE http://api.com      # DELETE request

  Options used with curl command:
      -X specifies the HTTP method you want to use (default is GET).
      -d stands for data. It is used to send request body data. 
         It automatically sets Content-Type to application/x-www-form-urlencoded unless you specify otherwise.

      Example:
        curl -X POST http://api.com \
            -H "Content-Type: application/json" \
            -d '{"name":"test"}'

  Using -d alone, without -X:
    If you provide -d without -X, curl automatically switches the HTTP method to POST.
    Example:
      curl http://api.com -d "name=test"

      Even though you did nott write -X POST, curl sends a POST request.
      The body will contain: name=test.
      So in most cases, you do not need to explicitly write -X POST when using -d.

🔹ping
    It is used to check connectivity. it also Measures network latency.
    Example: ping google.com


=========================================== Logs commands ============================================

🔹tail -f log/production.log
    This is used to view the end of a file. It is very handy for checking logs or the latest content in a file without opening the whole file.
    By default, shows the last 10 lines of the file.
    To show a specific number of lines, we have to pass the option.
      Example: tail -n 20 filename.txt

    Note: tail command is very usefuk in production.
         Example:   tail -f log/production.log
                    tail -n 50 -f log/production.log | grep "ERROR"
                    tail -n 20 -f log/production.log
                    tail -n 50 -f /var/log/syslog

         Here, the option -f is used to follow real-time updates. It keeps the terminal open and prints new lines as they are added.

🔹grep "ERROR" file.log
   It is used to Search inside file.
   Example: 
    grep "ERROR" log/production.log
    grep -i "timeout" file.log

   Here:
      -i → case insensitive
      -r → recursive

=========================================== Disk & Memory based commands ============================

🔹df -h
  This shows disk free space.
  -h means: human readable (MB, GB)

🔹du -sh
    This shows Disk usage of directory. Example: du -sh log/
    Here: 
      -s means: summary
      -h means: readable

🔹free -m
    This commands show Memory usage in MB.
    This will show:
        Total memory
        Used memory
        Free memory
        Buff/cache memory

=====================================================================================================

Question: Production is slow. What will you check?
Answer:
  CPU usage → top
  Memory → free -m
  Disk → df -h
  Logs → tail -f
  DB connections












======================================= 🔸Permissions based commands ==========================================

🔸What is chmod 755 ?
    When you run: chmod 755 myfile.txt
    You are telling Linux: “Set permissions for this file using the number 755.”

    🔹The 3 Permission Groups:
      Every file has three types of permissions, one for each class: owner, group, and others.
        Owner permissions → apply to the files owner
        Group permissions → apply to users in the group
        Others permissions → apply to everyone else

      So 755 actually means:
        Leftmost digit → Represents Owner permissions
        Middle digit → Represents Group permissions
        Rightmost digit → Represents Others permissions

        7   5   5
        │   │   │
        │   │   └── Others
        │   └────── Group
        └────────── Owner

    🔹What Do the Numbers in 755 Mean?
      Each number is made from adding:
        +-----------------------+
        | Number |	Permission  |
        |--------|--------------|
        |   4    |	Read (r)    |
        |   2    |	Write (w)   |
        |   1    |	Execute (x) |
        +-----------------------+

      You add them together to form a number which represents combination of permissions.
      What is 7?
        7 = 4 + 2 + 1
        So 7 means: rwx (Read, Write, Execute)

      What is 5?
        5 = 4 + 1
        So 5 means: r-x (Read, Execute — but NO write)

      So What Does 755 Mean?
        Owner  → 7 → rwx
        Group  → 5 → r-x
        Others → 5 → r-x

      That means:
        The owner can read, write i.e edit, and execute the file
        Everyone else can read and execute it
        But only the owner can modify it

 🔹Real Example: Suppose you have a file script.sh
    ➤You run: chmod 755 script.sh
      Now:
        Owner can read, edit/write and execute
        Group can read, execute, cannot edit
        Others can read, execute, cannot edit it

      So 755 means: rwxr-xr-x

    ➤You run: chmod 777 script.sh
      You (owner) can read, edit and execute
      Group can read, edit and execute
      Others can read, edit and execute

      So 777 means: rwxrwxrwx


🔸Why chmod +x bin/rails?
  That command just adds execute permission.
    +x means: “Allow this file to be run like a program.”
  
  Without execute permission, you can not run a file like: ./bin/rails


=================================================================================================================
🔸chown
  It is used to change owner (and optionally group) of a file or directory.
  Every file in Unix/Linux has:
    Owner (user) → the main user who owns the file
    Group → the group associated with the file
    Permissions → access rights (r, w, x) for owner, group, others

  chown changes owner and/or group, which determines who can access the file according to its permissions.

  🔹Why Use chown?
    ➤1:Assign ownership to another user
       You created a file as root, but want mohan to own it.
       example: sudo chown alice file.txt
    
    ➤2:Assign group ownership
      Make file belong to staff group.
      example: sudo chown :staff file.txt

    ➤3:Assign both owner and group
      Example: Owner = alice, Group = staff
      sudo chown alice:staff file.txt

    ➤4:Recursively change ownership (directories + all contents)
       example: sudo chown -R alice:staff /var/www/html

    ➤5:Fix permissions for multiple users in shared directories
       example: All files in /shared should belong to developers group
       sudo chown -R :developers /shared

    ➤6:Make root the owner as well as group (common for system files)
       sudo chown root:root file.txt

🔸Simple Rule of Thumb
    chown → who owns the file (owner + group)
    chmod → what everyone can do (owner, group, others)