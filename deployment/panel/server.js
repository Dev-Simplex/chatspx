const express = require('express');
const session = require('express-session');
const http = require('http');
const { Server } = require('socket.io');
const { Client } = require('ssh2');
const { execSync } = require('child_process');
const path = require('path');

// ============================================================
// CONFIG HARDCODED
// ============================================================

const AUTH = { user: 'admin', pass: 'Jzs72144#$GSpx' };
const GITHUB_REPO = 'Dev-Simplex/chatspx';
const SESSION_SECRET = 'spx-panel-s3cr3t-k3y-2026';
const PORT = 4000;
const STATUS_INTERVAL = 30000;
const HEARTBEAT_SIZE = 60;

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
  { id: 'producao', name: 'PRODUCAO', ip: '192.168.8.229', user: 'chatwoot', type: 'local', active: true, label: 'Proxmox' },
  { id: 'catatau', name: 'CATATAU', ip: '54.165.136.136', user: 'ubuntu', type: 'key', active: true, label: 'AWS EC2' },
  { id: 'sentinela', name: 'SENTINELA', ip: '54.152.144.236', user: 'ubuntu', type: 'key', active: true, label: 'AWS EC2' },
  { id: 'tozi', name: 'TOZI', ip: '54.91.152.38', user: 'ubuntu', type: 'key', active: false, label: 'AWS EC2' },
  { id: 'alternativo', name: 'ALTERNATIVO', ip: '192.168.8.169', user: 'simplexia', type: 'password', active: true, label: 'Proxmox' },
];

const BRANCHES = ['producao', 'homologacao', 'develop'];
const BRANCH_REGEX = /^[a-zA-Z0-9._\-/]{1,100}$/;

// ============================================================
// APP
// ============================================================

const app = express();
const server = http.createServer(app);
const io = new Server(server);

const sessionMiddleware = session({
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 4 * 60 * 60 * 1000 },
});

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(sessionMiddleware);
app.use(express.static(path.join(__dirname, 'public')));
io.engine.use(sessionMiddleware);

// ============================================================
// STATE
// ============================================================

const vmStatus = {};
const heartbeats = {};
const deployLocks = new Map();

VMS.forEach(vm => {
  vmStatus[vm.id] = { online: false, cpu: null, ram: null, disk: null, commit: null, branch: null, uptime: null, lastCheck: null, ping: null, chatwootStatus: null };
  heartbeats[vm.id] = [];
});

// ============================================================
// SSH
// ============================================================

function getSSHConfig(vm) {
  const config = { host: vm.ip, port: 22, username: vm.user, readyTimeout: 10000, keepaliveInterval: 5000 };
  if (vm.type === 'key') config.privateKey = SSH_KEY;
  else if (vm.type === 'password') config.password = SSH_PASSWORD;
  else if (vm.type === 'local') config.privateKey = SSH_KEY;
  return config;
}

function sshExec(vm, command, timeout = 15000) {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const timer = setTimeout(() => { conn.end(); reject(new Error('timeout')); }, timeout);
    conn.on('ready', () => {
      conn.exec(command, (err, stream) => {
        if (err) { clearTimeout(timer); conn.end(); return reject(err); }
        let stdout = '', stderr = '';
        stream.on('data', d => { stdout += d.toString(); });
        stream.stderr.on('data', d => { stderr += d.toString(); });
        stream.on('close', (code) => { clearTimeout(timer); conn.end(); resolve({ stdout: stdout.trim(), stderr: stderr.trim(), code }); });
      });
    });
    conn.on('error', err => { clearTimeout(timer); reject(err); });
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
      stream.on('close', code => { conn.end(); onDone(null, code); });
    });
  });
  conn.on('error', err => onDone(err));
  conn.connect(getSSHConfig(vm));
  return conn;
}

function execLocal(command) {
  try {
    return execSync(command, { encoding: 'utf8', timeout: 10000 }).trim();
  } catch { return ''; }
}

// ============================================================
// STATUS CHECK
// ============================================================

const METRICS_CMD_REMOTE = `echo "---METRICS---" && LC_ALL=C top -bn1 | grep 'Cpu(s)' | awk '{printf "%.0f", 100-$8}' && echo "" && free | awk '/Mem:/{printf "%.0f", $3/$2*100}' && echo "" && df / | awk 'NR==2{gsub(/%/,"",$5); print $5}' && echo "" && sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse --short HEAD' && echo "" && sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse --abbrev-ref HEAD' && echo "" && uptime -p && echo "" && sudo systemctl is-active chatwoot.target 2>/dev/null || echo unknown`;

const METRICS_CMD_LOCAL = `echo "---METRICS---" && LC_ALL=C top -bn1 | grep 'Cpu(s)' | awk '{printf "%.0f", 100-$8}' && echo "" && free | awk '/Mem:/{printf "%.0f", $3/$2*100}' && echo "" && df / | awk 'NR==2{gsub(/%/,"",$5); print $5}' && echo "" && cd /home/chatwoot/chatwoot && git rev-parse --short HEAD && echo "" && git rev-parse --abbrev-ref HEAD && echo "" && uptime -p && echo "" && systemctl is-active chatwoot.target 2>/dev/null || echo unknown`;

async function checkVM(vm) {
  if (!vm.active) {
    vmStatus[vm.id] = { ...vmStatus[vm.id], online: false, lastCheck: new Date().toISOString(), chatwootStatus: 'not_installed' };
    addHeartbeat(vm.id, false, null);
    return;
  }

  const startTime = Date.now();

  try {
    let result;
    if (vm.type === 'local') {
      const output = execLocal(METRICS_CMD_LOCAL);
      result = { stdout: output, code: 0 };
    } else {
      result = await sshExec(vm, METRICS_CMD_REMOTE, 12000);
    }

    const ping = Date.now() - startTime;
    const lines = result.stdout.split('\n').map(l => l.trim());
    const metricsIdx = lines.indexOf('---METRICS---');
    const data = metricsIdx >= 0 ? lines.slice(metricsIdx + 1) : lines;

    const cpu = parseFloat(data[0]) || 0;
    const ram = parseFloat(data[1]) || 0;
    const disk = parseFloat(data[2]) || 0;

    vmStatus[vm.id] = {
      online: true,
      cpu: Math.min(cpu, 100),
      ram: Math.min(ram, 100),
      disk: Math.min(disk, 100),
      commit: data[3] || null,
      branch: data[4] || null,
      uptime: data[5] || null,
      chatwootStatus: data[6] || 'unknown',
      lastCheck: new Date().toISOString(),
      ping,
    };
    addHeartbeat(vm.id, true, ping);
  } catch {
    const ping = Date.now() - startTime;
    vmStatus[vm.id] = { ...vmStatus[vm.id], online: false, lastCheck: new Date().toISOString(), ping };
    addHeartbeat(vm.id, false, ping);
  }
}

function addHeartbeat(vmId, online, ping) {
  heartbeats[vmId].push({ time: new Date().toISOString(), online, ping });
  if (heartbeats[vmId].length > HEARTBEAT_SIZE) heartbeats[vmId].shift();
}

function getUptimePercent(vmId) {
  const hb = heartbeats[vmId];
  if (hb.length === 0) return null;
  const online = hb.filter(h => h.online).length;
  return ((online / hb.length) * 100).toFixed(1);
}

async function checkAllVMs() {
  await Promise.allSettled(VMS.map(vm => checkVM(vm)));
  io.emit('status:update', getPayload());
}

function getPayload() {
  return VMS.map(vm => ({
    ...vm,
    status: vmStatus[vm.id],
    heartbeat: heartbeats[vm.id],
    uptimePercent: getUptimePercent(vm.id),
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

  return new Promise(resolve => {
    const ts = () => new Date().toLocaleTimeString('pt-BR');
    socket.emit('deploy:log', { vmId: vm.id, data: `[${ts()}] [${vm.name}] Iniciando deploy (branch: ${branch})...\n` });

    let cmd;
    if (vm.type === 'local') {
      cmd = `cd /home/chatwoot/chatwoot && git fetch origin && git checkout ${branch} && git pull origin ${branch} && source /usr/local/rvm/scripts/rvm && rvm use 3.4.4 && bundle install --jobs $(nproc) --retry 3 && pnpm install --frozen-lockfile 2>/dev/null || pnpm install && RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile && RAILS_ENV=production bundle exec rails db:migrate && sudo systemctl restart chatwoot.target && echo '=== DEPLOY CONCLUIDO ==='`;
    } else {
      cmd = `sudo wget -q https://raw.githubusercontent.com/${GITHUB_REPO}/${branch}/deployment/setup_spx_24.04.sh -O /usr/local/bin/cwctl && sudo chmod +x /usr/local/bin/cwctl && echo 'y' | sudo cwctl -U ${branch}`;
    }

    sshExecStream(vm, cmd,
      data => socket.emit('deploy:log', { vmId: vm.id, data }),
      (err, code) => {
        deployLocks.delete(vm.id);
        io.emit('deploy:lock', { vmId: vm.id, locked: false });
        if (err) {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[ERRO] ${err.message}\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: false, vmName: vm.name });
        } else {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[${ts()}] [${vm.name}] Finalizado (exit: ${code})\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: code === 0, vmName: vm.name });
        }
        setTimeout(() => checkVM(vm).then(() => io.emit('status:update', getPayload())), 5000);
        resolve();
      }
    );
  });
}

// ============================================================
// AUTH
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

app.post('/api/logout', (req, res) => { req.session.destroy(); res.json({ success: true }); });

app.get('/api/status', requireAuth, (req, res) => {
  res.json({ vms: getPayload(), branches: BRANCHES, github: GITHUB_REPO });
});

app.get('/api/health', (req, res) => { res.json({ status: 'ok', uptime: process.uptime() }); });

// ============================================================
// SOCKET.IO
// ============================================================

io.use((socket, next) => {
  if (socket.request.session?.authenticated) return next();
  next(new Error('Nao autenticado'));
});

io.on('connection', socket => {
  socket.emit('status:update', getPayload());

  socket.on('deploy', async ({ vmIds, branch }) => {
    if (!BRANCH_REGEX.test(branch)) { socket.emit('deploy:log', { vmId: 'system', data: '[ERRO] Branch invalida\n' }); return; }
    const selected = VMS.filter(v => vmIds.includes(v.id) && v.active);
    if (!selected.length) { socket.emit('deploy:log', { vmId: 'system', data: '[ERRO] Nenhuma VM selecionada\n' }); return; }
    socket.emit('deploy:start', { vmIds: selected.map(v => v.id), branch });
    for (const vm of selected) await deployVM(vm, branch, socket);
    socket.emit('deploy:allDone');
  });

  socket.on('refresh', () => checkAllVMs());
});

// ============================================================
// START
// ============================================================

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ChatSPX Panel v2 rodando em http://0.0.0.0:${PORT}`);
  checkAllVMs();
  setInterval(checkAllVMs, STATUS_INTERVAL);
});
