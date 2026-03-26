const express = require('express');
const session = require('express-session');
const http = require('http');
const { Server } = require('socket.io');
const { Client } = require('ssh2');
const path = require('path');

// ============================================================
// CONFIGURACAO HARDCODED
// ============================================================

const AUTH = { user: 'admin', pass: 'Jzs72144#$GSpx' };
const GITHUB_REPO = 'Dev-Simplex/chatspx';
const SESSION_SECRET = 'spx-panel-s3cr3t-k3y-2026';
const PORT = 4000;
const STATUS_INTERVAL = 30000; // 30s

const SSH_KEY = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAjGyZwywsYUjDVYa8yyafsTpj+39b0bTN0+GgEGwi1ZQKQFGV
mdhdPr4Vf5RqAgDMvfy6zaBwJ69gJv7v8v7eC8cl8Y1sEn5Yyhk8SweIT4IzXO36
WtTm73fa3mvogmQ6eSmO/TgoacauRiZ+moyUTGpXXp1PGHnAxCBRsOHpf+ddub23
NwH39TKnKseTC377Da/fSXWXTj58oNFK3mIJIOTBImxxjzEQW7omTH9r1tKEI5tS
TAbfv6CXJrJ08+bLPL+hqNqVANuxsVrzck8+6e6re4B3Bf0D7YhuVuCl/LG/A8du
CaEnOS9pCusNBK7NhY0SguVHQupTYbNDBnvgjwIDAQABAoIBAQCFP5g4p3YFanJQ
eeY0L5ZhKjMttxB90b9uSy8D5li3qh6AIep/bdwtaVolEcP12qRts5/e91r1jWkE
F+3A+y/gpTzQFY5zjgja3U9lMuSZ7cana/qgrl3k5ip93I9pC4qg5lqU1fEjTjCY
yHZiWPtv94ioc0VWyFGuyaw62GQlxRI0h+gWC6nsmCpfDaFYnDWAVNeFRwez876E
5xjF9dyislrl+7EPH54kJQIRGY3BSC0cXRMuliQvOffdkcmtkmgPET9myPpFXT/z
XwI/VETApP5iG2Mg6H9CTDi7ziLxuKgVUd6kkTbWTRP9ZbyhmhRabGKFqLotVvmh
MO5QFoPhAoGBAMHGimE7EpZ1wffGsD+nbMkWDJBi9ytf+PgZLwaPnbrq6WEPL+3d
Kv/m3dSZpoheq4xxJp8zcCYk3/xW4JN7+AHvQznkuf+RxA+srGTPqrC87YVwhrwp
AG2xwPUarXfvo72lGZQLDkmo0jvBfIbsyik2pBccBFUanyrt4OJCeEMVAoGBALmE
Rohts3oY5YReNnH50yMtr9K4VB2rzL6SDODp0XOJlcF833OQO3V+evpzt6Xj+z1t
4bD081HLw2yX0/VlLWrDoCSuxOENtpNglYFjCjvbhcV46bx1kGMDGsvpbdI4Ntm+
eK6tpJXnr0BgoCDLxnOETpMYt3wWE8UcdUOARM4TAoGAWnYYdenA9LLGuahs8Vp0
469CcElzQDGOpiwDkxmKtg8iomgXpQDiKRMbLjwIzZL8nRTZxeqaiYQfeMsKDnAK
SMTs6mMIHfJryDGBTZLRCa85Z1kv3Tl69LrN7N7map5aH5eqyD0dD3AbrT/XpZl3
iyPyGMPAlgZWlhD1Mkt7nz0CgYEAp1/oIv6WhvofWSWHCZ3UGFEH6J3Vhk+SEf3D
EMjj59GiA0eecq0WeBL88Sml702ZRvr0PKtDO/ETB86TtTrrlv+YZIApsMKmjqD9
QhcRDKAqONe2Sgnnku0iKAcaxidhlWJ7j12quHSncPW8gtpW2bHtElmicZmZjKT4
R0ZazXECgYBQ7jK8T14wiK/DGFRSGDaS9DkPo1DmPMQifgW8uNJochy9C03OgKu9
vNDrUj26VXHayx9UYKjIANs55+D7GakBRtolOYgbtr3qvB2HKwZqqRQf8YDF5VqZ
fKAPv6FYiUrOwQkmxFO4kQdUROt6KXJpZYcWtfTdBwV4y30WA7bQQg==
-----END RSA PRIVATE KEY-----`;

const SSH_PASSWORD = 'Jzs72144#$GSpx';

const VMS = [
  { id: 'producao', name: 'PRODUCAO', ip: '192.168.8.229', user: 'chatwoot', type: 'key', active: true },
  { id: 'catatau', name: 'CATATAU', ip: '54.165.136.136', user: 'ubuntu', type: 'key', active: true },
  { id: 'sentinela', name: 'SENTINELA', ip: '54.152.144.236', user: 'ubuntu', type: 'key', active: true },
  { id: 'tozi', name: 'TOZI', ip: '54.91.152.38', user: 'ubuntu', type: 'key', active: false },
  { id: 'alternativo', name: 'ALTERNATIVO', ip: '192.168.8.169', user: 'simplexia', type: 'password', active: true },
];

const BRANCHES = ['producao', 'homologacao', 'develop'];
const BRANCH_REGEX = /^[a-zA-Z0-9._\-/]{1,100}$/;

// ============================================================
// APP SETUP
// ============================================================

const app = express();
const server = http.createServer(app);
const io = new Server(server);

const sessionMiddleware = session({
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 4 * 60 * 60 * 1000 }, // 4h
});

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(sessionMiddleware);
app.use(express.static(path.join(__dirname, 'public')));

// Share session with Socket.IO
io.engine.use(sessionMiddleware);

// ============================================================
// STATE
// ============================================================

const vmStatus = {};
const deployLocks = new Map(); // vmId -> true

VMS.forEach(vm => {
  vmStatus[vm.id] = {
    online: false,
    cpu: null,
    ram: null,
    disk: null,
    commit: null,
    branch: null,
    uptime: null,
    lastCheck: null,
    chatwootStatus: null,
  };
});

// ============================================================
// SSH HELPERS
// ============================================================

function getSSHConfig(vm) {
  const config = {
    host: vm.ip,
    port: 22,
    username: vm.user,
    readyTimeout: 10000,
    keepaliveInterval: 5000,
  };
  if (vm.type === 'key') {
    config.privateKey = SSH_KEY;
  } else {
    config.password = SSH_PASSWORD;
  }
  return config;
}

function sshExec(vm, command, timeout = 15000) {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const timer = setTimeout(() => {
      conn.end();
      reject(new Error('SSH timeout'));
    }, timeout);

    conn.on('ready', () => {
      conn.exec(command, (err, stream) => {
        if (err) { clearTimeout(timer); conn.end(); return reject(err); }
        let stdout = '';
        let stderr = '';
        stream.on('data', d => { stdout += d.toString(); });
        stream.stderr.on('data', d => { stderr += d.toString(); });
        stream.on('close', (code) => {
          clearTimeout(timer);
          conn.end();
          resolve({ stdout: stdout.trim(), stderr: stderr.trim(), code });
        });
      });
    });

    conn.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });

    conn.connect(getSSHConfig(vm));
  });
}

function sshExecStream(vm, command, onData, onDone) {
  const conn = new Client();

  conn.on('ready', () => {
    conn.exec(command, { pty: true }, (err, stream) => {
      if (err) { conn.end(); return onDone(err); }
      stream.on('data', d => onData(d.toString()));
      stream.stderr.on('data', d => onData(d.toString()));
      stream.on('close', (code) => {
        conn.end();
        onDone(null, code);
      });
    });
  });

  conn.on('error', (err) => onDone(err));
  conn.connect(getSSHConfig(vm));
  return conn;
}

// ============================================================
// VM STATUS CHECK
// ============================================================

async function checkVM(vm) {
  if (!vm.active) {
    vmStatus[vm.id] = { ...vmStatus[vm.id], online: false, lastCheck: new Date().toISOString(), chatwootStatus: 'not_installed' };
    return;
  }

  try {
    const cmd = vm.user === 'chatwoot'
      ? "echo OK && top -bn1 | grep 'Cpu(s)' | awk '{print 100-$8}' && free -m | awk '/Mem:/{printf \"%.0f\", $3/$2*100}' && df -h / | awk 'NR==2{print $5}' | tr -d '%' && cd ~/chatwoot && git rev-parse --short HEAD && git rev-parse --abbrev-ref HEAD && uptime -p && systemctl is-active chatwoot.target 2>/dev/null || echo inactive"
      : "echo OK && top -bn1 | grep 'Cpu(s)' | awk '{print 100-$8}' && free -m | awk '/Mem:/{printf \"%.0f\", $3/$2*100}' && df -h / | awk 'NR==2{print $5}' | tr -d '%' && sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse --short HEAD && git rev-parse --abbrev-ref HEAD' && uptime -p && sudo systemctl is-active chatwoot.target 2>/dev/null || echo inactive";

    const result = await sshExec(vm, cmd, 12000);
    const lines = result.stdout.split('\n').map(l => l.trim());

    vmStatus[vm.id] = {
      online: lines[0] === 'OK',
      cpu: parseFloat(lines[1]) || null,
      ram: parseFloat(lines[2]) || null,
      disk: parseFloat(lines[3]) || null,
      commit: lines[4] || null,
      branch: lines[5] || null,
      uptime: lines[6] || null,
      chatwootStatus: lines[7] || 'unknown',
      lastCheck: new Date().toISOString(),
    };
  } catch {
    vmStatus[vm.id] = {
      ...vmStatus[vm.id],
      online: false,
      lastCheck: new Date().toISOString(),
    };
  }
}

async function checkAllVMs() {
  await Promise.allSettled(VMS.map(vm => checkVM(vm)));
  io.emit('status:update', getStatusPayload());
}

function getStatusPayload() {
  return VMS.map(vm => ({
    ...vm,
    status: vmStatus[vm.id],
    deploying: deployLocks.has(vm.id),
  }));
}

// ============================================================
// DEPLOY
// ============================================================

function deployVM(vm, branch, socket) {
  if (deployLocks.has(vm.id)) {
    socket.emit('deploy:log', { vmId: vm.id, data: `[ERRO] Deploy ja em andamento para ${vm.name}\n` });
    return Promise.resolve();
  }

  deployLocks.set(vm.id, true);
  io.emit('deploy:lock', { vmId: vm.id, locked: true });

  return new Promise((resolve) => {
    const timestamp = () => new Date().toLocaleTimeString('pt-BR');

    socket.emit('deploy:log', { vmId: vm.id, data: `[${timestamp()}] [${vm.name}] Iniciando deploy (branch: ${branch})...\n` });

    let cmd;
    if (vm.user === 'chatwoot') {
      // VM local (producao) - roda direto
      cmd = `cd ~/chatwoot && git fetch origin && git checkout ${branch} && git pull origin ${branch} && source /usr/local/rvm/scripts/rvm && rvm use 3.4.4 && bundle install --jobs $(nproc) --retry 3 && pnpm install --frozen-lockfile 2>/dev/null || pnpm install && RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile && RAILS_ENV=production bundle exec rails db:migrate && sudo systemctl restart chatwoot.target && echo '=== DEPLOY CONCLUIDO COM SUCESSO ==='`;
    } else {
      // VM remota - roda via sudo cwctl
      cmd = `sudo wget -q https://raw.githubusercontent.com/${GITHUB_REPO}/${branch}/deployment/setup_spx_24.04.sh -O /usr/local/bin/cwctl && sudo chmod +x /usr/local/bin/cwctl && echo 'y' | sudo cwctl -U ${branch}`;
    }

    const conn = sshExecStream(vm, cmd,
      (data) => {
        socket.emit('deploy:log', { vmId: vm.id, data });
      },
      (err, code) => {
        deployLocks.delete(vm.id);
        io.emit('deploy:lock', { vmId: vm.id, locked: false });

        if (err) {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[ERRO] ${err.message}\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: false });
        } else {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[${timestamp()}] [${vm.name}] Finalizado (exit code: ${code})\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: code === 0 });
        }

        // Refresh status after deploy
        setTimeout(() => checkVM(vm).then(() => io.emit('status:update', getStatusPayload())), 5000);
        resolve();
      }
    );

    // Store connection for potential cancel
    socket.deployConns = socket.deployConns || {};
    socket.deployConns[vm.id] = conn;
  });
}

// ============================================================
// AUTH MIDDLEWARE
// ============================================================

function requireAuth(req, res, next) {
  if (req.session?.authenticated) return next();
  res.status(401).json({ error: 'Nao autenticado' });
}

// ============================================================
// ROUTES
// ============================================================

app.post('/api/login', (req, res) => {
  const { user, pass } = req.body;
  if (user === AUTH.user && pass === AUTH.pass) {
    req.session.authenticated = true;
    res.json({ success: true });
  } else {
    res.status(401).json({ error: 'Credenciais invalidas' });
  }
});

app.post('/api/logout', (req, res) => {
  req.session.destroy();
  res.json({ success: true });
});

app.get('/api/status', requireAuth, (req, res) => {
  res.json({
    vms: getStatusPayload(),
    branches: BRANCHES,
    github: GITHUB_REPO,
  });
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// ============================================================
// SOCKET.IO
// ============================================================

io.use((socket, next) => {
  const req = socket.request;
  if (req.session?.authenticated) return next();
  next(new Error('Nao autenticado'));
});

io.on('connection', (socket) => {
  // Send current status on connect
  socket.emit('status:update', getStatusPayload());

  // Deploy request
  socket.on('deploy', async ({ vmIds, branch }) => {
    if (!BRANCH_REGEX.test(branch)) {
      socket.emit('deploy:log', { vmId: 'system', data: '[ERRO] Nome de branch invalido\n' });
      return;
    }

    const selectedVMs = VMS.filter(vm => vmIds.includes(vm.id) && vm.active);
    if (selectedVMs.length === 0) {
      socket.emit('deploy:log', { vmId: 'system', data: '[ERRO] Nenhuma VM selecionada\n' });
      return;
    }

    socket.emit('deploy:start', { vmIds: selectedVMs.map(v => v.id), branch });

    // Deploy sequentially
    for (const vm of selectedVMs) {
      await deployVM(vm, branch, socket);
    }

    socket.emit('deploy:allDone');
  });

  // Refresh status on demand
  socket.on('refresh', () => {
    checkAllVMs();
  });
});

// ============================================================
// START
// ============================================================

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ChatSPX Panel rodando em http://0.0.0.0:${PORT}`);
  checkAllVMs();
  setInterval(checkAllVMs, STATUS_INTERVAL);
});
