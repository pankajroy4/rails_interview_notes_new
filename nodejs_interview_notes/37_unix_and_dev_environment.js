/*
===============================================================================================
                       UNIX / LINUX COMMANDS + NODE DEV ENVIRONMENT
===============================================================================================
(Mirrors my unix_command.rb. The Linux part is language-agnostic and transfers directly. I've
added the Node-specific tooling — nvm, npm scripts, pm2, process inspection — that a Node dev is
expected to know on top of the shell basics.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: Command structure + the flags refresher (from my Rails notes)
-----------------------------------------------------------------------------------------------
Answer -> Syntax: `command -options arguments`.
  - Short flags: single dash, one letter each, combinable -> `rm -rf dir` == `rm -r -f dir`.
  - Long flags: double dash, descriptive -> `rm --recursive` == `rm -r`.
  - `--` alone means "stop parsing options" -> `rm -- -file.txt` deletes a file literally named
    "-file.txt" (otherwise it's read as flags).
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Everyday Linux commands a backend dev must know
-----------------------------------------------------------------------------------------------
Answer ->
  FILES/NAV:  ls -la, cd, pwd, mkdir -p, rm -rf, cp -r, mv, touch, cat, less, tail -f file.log
  SEARCH:     grep -r "pattern" .   find . -name "*.js"   which node   locate
  TEXT:       head/tail, wc -l, sort, uniq, cut, sed, awk, `grep "ERROR" app.log | tail -50`
  PERMS:      chmod +x script.sh, chmod 644, chown user:group file, sudo
  PROCESS:    ps aux | grep node, top / htop, kill <pid>, kill -9 <pid>, kill -SIGTERM <pid>
  NETWORK:    curl -i URL, wget, netstat -tulpn / ss -tulpn (what's on a port), ping, nslookup/dig
  DISK/MEM:   df -h (disk), du -sh dir (dir size), free -h (memory)
  PIPES/REDIR: cmd1 | cmd2 (pipe), > file (overwrite), >> file (append), 2>&1 (stderr->stdout)
  ENV:        export VAR=value, echo $PATH, env, printenv
  ARCHIVE:    tar -czf out.tar.gz dir/ , tar -xzf out.tar.gz
*/

/*
-----------------------------------------------------------------------------------------------
Q3: Signals (directly relevant to Node graceful shutdown)
-----------------------------------------------------------------------------------------------
Answer -> A signal is an OS message to a process. The ones a Node dev cares about:
  - SIGTERM (15): "please terminate" — what Docker/k8s/PM2 send to stop a process. I handle this to
    do GRACEFUL SHUTDOWN (drain requests/jobs, close DB/Redis) — file 08.
  - SIGINT  (2):  Ctrl-C in the terminal.
  - SIGKILL (9):  "die now," cannot be caught/handled — last resort (`kill -9`). Loses in-flight work.
  - SIGHUP (1):   terminal closed / reload config in some daemons.
  `kill -SIGTERM <pid>` vs `kill -9 <pid>` is the difference between a clean shutdown and a hard kill.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: Node version management — nvm (the rbenv/rvm equivalent)
-----------------------------------------------------------------------------------------------
Answer -> nvm (Node Version Manager) installs + switches Node versions per project, like rbenv for
Ruby. An .nvmrc file pins the version so the team + CI use the same Node.
  nvm install 20            # install Node 20
  nvm use 20                # switch
  nvm alias default 20      # default for new shells
  node -v / npm -v          # check versions
  # .nvmrc contains "20"; `nvm use` reads it.
*/

/*
-----------------------------------------------------------------------------------------------
Q5: npm scripts + npx (the rake/bin equivalent)
-----------------------------------------------------------------------------------------------
Answer -> package.json "scripts" are the project's command shortcuts (like rake tasks / bin/ scripts):
  "scripts": {
    "dev":   "tsx watch src/index.ts",     # run dev server with reload
    "build": "tsc",
    "start": "node dist/server.js",
    "test":  "jest",
    "lint":  "eslint .",
    "migrate": "prisma migrate deploy"
  }
  Run with: npm run dev / npm test / npm start.
  npx runs a package binary without a global install: `npx prisma studio`, `npx eslint .`.
  nodemon / tsx watch auto-restart the server on file changes in dev (like Rails' reloading).
*/

/*
-----------------------------------------------------------------------------------------------
Q6: Running + inspecting Node in production (pm2, logs, ports)
-----------------------------------------------------------------------------------------------
Answer ->
  PM2 (process manager — file 18):
    pm2 start dist/server.js -i max --name api   # cluster mode, one process per core
    pm2 list / pm2 monit                          # status / live dashboard
    pm2 logs api                                  # tail logs
    pm2 reload api                                # zero-downtime reload (graceful)
    pm2 restart / stop / delete api
    pm2 startup && pm2 save                       # survive server reboot

  DEBUG / INSPECT:
    node --inspect dist/server.js                 # attach Chrome DevTools / VS Code debugger
    NODE_OPTIONS=--max-old-space-size=2048 node ...# raise heap limit
    lsof -i :3000   /   ss -tulpn | grep 3000     # what's holding a port (EADDRINUSE)
    kill -9 $(lsof -ti :3000)                      # free a stuck port in dev
*/

/*
-----------------------------------------------------------------------------------------------
Q7: A couple of real "debug it on the server" one-liners
-----------------------------------------------------------------------------------------------
Answer ->
  tail -f /var/log/app.log | grep -i error        # watch errors live
  grep -c "ERROR" app.log                          # count errors
  ps aux --sort=-%mem | head                       # top memory consumers (find a leaking node proc)
  curl -i http://localhost:3000/health             # check the app is up + see status/headers
  df -h                                            # disk full? (a classic prod outage cause)
  journalctl -u my-node-service -f                 # systemd service logs (if not on PM2/Docker)
  These shell skills + log-grepping are how I'd triage a production incident on the box itself.
*/

module.exports = {};
